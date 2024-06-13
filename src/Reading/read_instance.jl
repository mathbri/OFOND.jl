# File containing all functions to read an instance

function read_node!(counts::Dict{Symbol,Int}, row::CSV.Row)
    nodeType = Symbol(nodeTypeStr)
    haskey(counts, nodeType) && counts[nodeType] += 1
    return NetworkNode(
        row.point_account,
        nodeType,
        row.point_name,
        LLA(row.point_latitude, row.point_longitude),
        row.point_country,
        row.point_continent,
        nodeType in COMMON_NODE_TYPES,
        row.point_m3_cost,
    )
end

function read_and_add_nodes!(network::NetworkGraph, node_file::String)
    counts = Dict([(nodeType, 0) for nodeType in OFOND.NODE_TYPES])
    # Reading .csv file
    csv_reader = CSV.File(
        node_file; types=Dict("point_account" => String15, "point_type" => String15)
    )
    @info "Reading nodes from CSV file $(node_file) ($(length(csv_reader)) lines)"
    for row in csv_reader
        node = read_node!(counts, row)
        add_node!(network, node)
    end
    @info "Read $(nv(network.graph)) nodes : $counts"
end

function src_dst_hash(row::CSV.Row)
    return hash(row.src_account, Symbol(row.src_type)),
    hash(row.dst_account, Symbol(row.dst_type))
end

function is_common_arc(row::CSV.Row)
    return Symbol(row.src_type) in COMMON_NODE_TYPES &&
           Symbol(row.dst_type) in COMMON_NODE_TYPES
end

function read_leg!(counts::Dict{Symbol,Int}, row::CSV.Row, isCommon::Bool)
    arcType = Symbol(arcTypeStr)
    haskey(counts, arcType) && counts[arcType] += 1
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

function read_and_add_legs!(network::NetworkGraph, leg_file::String)
    counts = Dict([(arcType, 0) for arcType in OFOND.ARC_TYPES])
    # Reading .csv file
    columns = ["src_account", "dst_account", "src_type", "dst_type", "leg_type"]
    csv_reader = CSV.File(leg_file; types=Dict([(column, String15) for column in columns]))
    @info "Reading legs from CSV file $(leg_file) ($(length(csv_reader)) lines)"
    for row in csv_reader
        src, dst = src_dst_hash(row)
        isCommon = is_common_arc(row)
        arc = read_leg!(counts, row, isCommon)
        add_arc!(network, arc, src, dst)
    end
    @info "Read $(ne(network.graph)) legs : $counts"
end

# TODO : adapt from here 

function bundle_hash(row::CSV.Row)
    return hash(row.supplier_account, hash(row.customer_account))
end

function order_hash(row::CSV.Row)
    return hash(row.delivery_time_step, bundle_hash(row))
end

function com_size(row::CSV.Row)
    return round(Int, max(1, row.size * 100))
end

function com_data_hash(row::CSV.Row)
    return hash(row.part_number, hash(com_size(row), hash(row.lead_time_cost)))
end

function get_bundle!(bundles::Dict{UInt,Bundle}, row::CSV.Row, network::NetworkGraph)
    supplierNode = network.graph[hash(row.supplier_account, :supplier)]
    customerNode = network.graph[hash(row.customer_account, :plant)]
    return get!(
        bundles, bundle_hash(row), Bundle(supplierNode, customerNode, length(bundles) + 1)
    )
end

function get_order!(orders::Dict{UInt,Order}, row::CSV.Row, bundle::Bundle)
    return get!(orders, order_hash(row), Order(bundle, row.delivery_time_step))
end

function get_com_data!(comDatas::Dict{UInt,CommodityData}, row::CSV.Row)
    return get!(
        comDatas,
        com_data_hash(row),
        CommodityData(row.part_number, com_size(row), row.lead_time_cost),
    )
end

function read_commodities(networkGraph::NetworkGraph, commodities_file::String)
    comDatas, orders = Dict{UInt,CommodityData}(), Dict{UInt,Order}()
    bundles, allDates = Dict{UInt,Bundle}(), Set{Date}()
    comCount, comUnique = 0, 0
    # Reading .csv file
    csv_reader = CSV.File(
        commodities_file;
        types=Dict("supplier_account" => String15, "customer_account" => String15),
    )
    println(
        "Reading commodity orders from CSV file $(file_name) ($(length(csv_reader)) lines)"
    )
    # Creating objects : each line is a commodity order
    println("Creating initial objects...")
    for row in csv_reader
        # Getting bundle, order and commodity data
        bundle = get_bundle!(bundles, row, networkGraph)
        order = get_order!(orders, row, bundle)
        comData = get_com_data!(comDatas, row)
        # If the order is new we have to add it to the bundle
        haskey(orders, orderKey) || push!(bundle.orders, order)
        # Creating (and Duplicating) commodity
        commodity = Commodity(order, comData)
        append!(order.content, [commodity for _ in 1:(row.quantity)])
        comCount, comUnique .+= row.quantity, 1
        # Is it a new time step ?
        push!(allDates, Date(row.delivery_date))
    end
    # Transforming dictionnaries into vectors
    bundleVector = collect(values(bundles))
    # Ordering the vector so that the idx field correspond to the actual idx in the vector
    sort!(bundleVector; by=bundle -> bundle.idx)
    println(
        "Read $(length(bundles)) bundles, $(length(orders)) orders and $comCount commodities ($comUnique without quantities) " *
        "on a $(length(allDates)) steps time horizon\n",
    )
    return bundleVector, sort(collect(allDates))
end

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