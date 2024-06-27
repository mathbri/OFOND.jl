# File containing all functions to read an instance

# Read a node for a csv row and update counts
function read_node!(counts::Dict{Symbol,Int}, row::CSV.Row)
    nodeType = Symbol(row.point_type)
    haskey(counts, nodeType) && (counts[nodeType] += 1)
    account, name, country, continent = promote(
        row.point_account, row.point_name, row.point_country, row.point_continent
    )
    return NetworkNode(
        account,
        nodeType,
        name,
        LLA(row.point_latitude, row.point_longitude),
        country,
        continent,
        nodeType in COMMON_NODE_TYPES,
        row.point_m3_cost,
    )
end

# Read and add nodes from the csv file given
function read_and_add_nodes!(network::NetworkGraph, node_file::String)
    counts = Dict([(nodeType, 0) for nodeType in OFOND.NODE_TYPES])
    # Reading .csv file
    csv_reader = CSV.File(
        node_file; types=Dict("point_account" => String, "point_type" => String)
    )
    @info "Reading nodes from CSV file $(basename(node_file)) ($(length(csv_reader)) lines)"
    for row in csv_reader
        node = read_node!(counts, row)
        add_node!(network, node)
    end
    @info "Read $(nv(network.graph)) nodes : $counts"
end

# Computes source and dest hash from a csv row
function src_dst_hash(row::CSV.Row)
    return hash(row.src_account, hash(Symbol(row.src_type))),
    hash(row.dst_account, hash(Symbol(row.dst_type)))
end

# Check if the arc described in the row is a common arc
function is_common_arc(row::CSV.Row)
    return Symbol(row.src_type) in COMMON_NODE_TYPES &&
           Symbol(row.dst_type) in COMMON_NODE_TYPES
end

# Read a leg for a csv row
function read_leg!(counts::Dict{Symbol,Int}, row::CSV.Row, isCommon::Bool)
    arcType = Symbol(row.leg_type)
    haskey(counts, arcType) && (counts[arcType] += 1)
    return NetworkArc(
        arcType,
        row.distance,
        floor(Int, row.travel_time),
        isCommon,
        row.unitCost,
        row.isLinear,
        row.carbonCost,
        row.capacity,
    )
end

# Read and add legs from the csv file
function read_and_add_legs!(network::NetworkGraph, leg_file::String)
    counts = Dict([(arcType, 0) for arcType in OFOND.ARC_TYPES])
    # Reading .csv file
    columns = ["src_account", "dst_account", "src_type", "dst_type", "leg_type"]
    csv_reader = CSV.File(leg_file; types=Dict([(column, String) for column in columns]))
    @info "Reading legs from CSV file $(basename(leg_file)) ($(length(csv_reader)) lines)"
    for row in csv_reader
        src, dst = src_dst_hash(row)
        arc = read_leg!(counts, row, is_common_arc(row))
        add_arc!(network, src, dst, arc)
    end
    @info "Read $(ne(network.graph)) legs : $counts"
end

# Computes bundle hash from a csv row
function bundle_hash(row::CSV.Row)
    return hash(row.supplier_account, hash(row.customer_account))
end

# Computes order hash from a csv row
function order_hash(row::CSV.Row)
    return hash(row.delivery_time_step, bundle_hash(row))
end

# Computes commodity size from a csv row
function com_size(row::CSV.Row)
    return round(Int, max(1, row.size * 100))
end

# Computes commodity data hash from a csv row
function com_data_hash(row::CSV.Row)
    return hash(row.part_number, hash(com_size(row), hash(row.lead_time_cost)))
end

# Get bundle data form already read bundles, creating one if needed
function get_bundle!(bundles::Dict{UInt,Bundle}, row::CSV.Row, network::NetworkGraph)
    # Get supplier and customer nodes
    if !haskey(network.graph, hash(row.supplier_account, hash(:supplier)))
        @warn "Supplier unknown in the network" :supplier = row.supplier_account :row = row
    elseif !haskey(network.graph, hash(row.customer_account, hash(:plant)))
        @warn "Customer unknown in the network" :customer = row.customer_account :row = row
    else
        supplierNode = network.graph[hash(row.supplier_account, hash(:supplier))]
        customerNode = network.graph[hash(row.customer_account, hash(:plant))]
        return get!(
            bundles,
            bundle_hash(row),
            Bundle(supplierNode, customerNode, length(bundles) + 1),
        )
    end
end

# Get order from already read orders, creating one if needed
function get_order!(orders::Dict{UInt,Order}, row::CSV.Row, bundle::Bundle)
    return get!(orders, order_hash(row), Order(bundle, row.delivery_time_step))
end

# Get commodity data from already read commodity data, creating one if needed
function get_com_data!(comDatas::Dict{UInt,CommodityData}, row::CSV.Row)
    return get!(
        comDatas,
        com_data_hash(row),
        CommodityData(row.part_number, com_size(row), row.lead_time_cost),
    )
end

# Read commodities data from the csv file
function read_commodities(networkGraph::NetworkGraph, commodities_file::String)
    comDatas, orders = Dict{UInt,CommodityData}(), Dict{UInt,Order}()
    bundles, allDates = Dict{UInt,Bundle}(), Set{Date}()
    comCount, comUnique = 0, 0
    # Reading .csv file
    csv_reader = CSV.File(
        commodities_file;
        types=Dict("supplier_account" => String, "customer_account" => String),
    )
    @info "Reading commodity orders from CSV file $(basename(commodities_file)) ($(length(csv_reader)) lines)"
    # Creating objects : each line is a commodity order
    for row in csv_reader
        # Getting bundle, order and commodity data
        bundle = get_bundle!(bundles, row, networkGraph)
        bundle === nothing && continue
        order = get_order!(orders, row, bundle)
        comData = get_com_data!(comDatas, row)
        # If the order is new (no commodities) we have to add it to the bundle
        length(order.content) == 0 && push!(bundle.orders, order)
        # Creating (and Duplicating) commodity
        commodity = Commodity(order, comData)
        append!(order.content, [commodity for _ in 1:(row.quantity)])
        comCount += row.quantity
        comUnique += 1
        # Is it a new time step ?
        push!(allDates, Date(row.delivery_date))
    end
    # Transforming dictionnaries into vectors (sorting the vector so that the idx field correspond to the actual idx in the vector)
    bundleVector = sort(collect(values(bundles)); by=bundle -> bundle.idx)
    @info "Read $(length(bundles)) bundles, $(length(orders)) orders and $comCount commodities ($comUnique without quantities) on a $(length(allDates)) steps time horizon"
    return bundleVector, sort(collect(allDates))
end

# Read instance from csv files
function read_instance(node_file::String, leg_file::String, commodities_file::String)
    networkGraph = NetworkGraph()
    read_and_add_nodes!(networkGraph, node_file)
    read_and_add_legs!(networkGraph, leg_file)
    bundles, dateHorizon = read_commodities(networkGraph, commodities_file)
    return Instance(
        networkGraph,
        TravelTimeGraph(),
        TimeSpaceGraph(),
        bundles,
        length(dateHorizon),
        dateHorizon,
    )
end