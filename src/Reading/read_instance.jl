# File containing all functions to read an instance

function read_node!(counts::Dict{Symbol,Int}, row::CSV.Row)
    nodeType = Symbol(row.point_type)
    haskey(counts, nodeType) && (counts[nodeType] += 1)
    account, country, continent = promote(
        row.point_account, row.point_country, row.point_continent
    )
    return NetworkNode(
        account,
        nodeType,
        country,
        continent,
        nodeType in COMMON_NODE_TYPES,
        row.point_m3_cost,
    )
end

function read_and_add_nodes!(network::NetworkGraph, node_file::String; verbose::Bool=false)
    counts = Dict([(nodeType, 0) for nodeType in OFOND.NODE_TYPES])
    # Reading .csv file
    csv_reader = CSV.File(
        node_file; types=Dict("point_account" => String, "point_type" => String)
    )
    @info "Reading nodes from CSV file $(basename(node_file)) ($(length(csv_reader)) lines)"
    ignored = Dict(:same_node => 0, :unknown_type => 0)
    for row in csv_reader
        node = read_node!(counts, row)
        added, ignore_type = add_node!(network, node; verbose=verbose)
        added || (ignored[ignore_type] += 1)
        if node.volumeCost < EPS && node.type in [:xdock, :iln]
            # println(row)
            # println(node)
            # @error "No volume cost on this platform"
            # throw(ErrorException("No volume cost on this platform"))
        end
    end
    ignoredStr = join(pairs(ignored), ", ")
    @info "Read $(nv(network.graph)) nodes : $counts" :ignored = ignoredStr
end

function src_dst_hash(row::CSV.Row)
    return hash(row.src_account, hash(Symbol(row.src_type))),
    hash(row.dst_account, hash(Symbol(row.dst_type)))
end

function is_common_arc(row::CSV.Row)
    # return Symbol(row.src_type) in COMMON_NODE_TYPES &&
    #        Symbol(row.dst_type) in COMMON_NODE_TYPES
    return Symbol(row.leg_type) in COMMON_ARC_TYPES
end

function read_leg!(counts::Dict{Symbol,Int}, row::CSV.Row, isCommon::Bool)
    arcType = Symbol(row.leg_type)
    haskey(counts, arcType) && (counts[arcType] += 1)
    shipmentFactor = if arcType == :oversea
        0.25
    elseif arcType == :outsource
        0.1
    else
        0.5
    end
    shipCost = if arcType == :oversea
        5e3 + 5e3 * rand()
    else
        row.shipment_cost
    end
    return NetworkArc(
        arcType,
        row.distance,
        # floor(Int, row.travel_time + 0.5),
        min(floor(Int, row.travel_time), 7),
        isCommon,
        # row.shipment_cost * shipmentFactor / 5,
        shipCost,
        row.is_linear,
        # false,
        row.carbon_cost,
        min(LAND_CAPACITY, row.capacity * VOLUME_FACTOR),
    )
end

function read_and_add_legs!(network::NetworkGraph, leg_file::String; verbose::Bool=false)
    counts = Dict([(arcType, 0) for arcType in OFOND.ARC_TYPES])
    # Reading .csv file
    columns = ["src_account", "dst_account", "src_type", "dst_type", "leg_type"]
    csv_reader = CSV.File(leg_file; types=Dict([(column, String) for column in columns]))
    @info "Reading legs from CSV file $(basename(leg_file)) ($(length(csv_reader)) lines)"
    ignored = Dict(
        :same_arc => 0, :unknown_type => 0, :unknown_source => 0, :unknown_dest => 0
    )
    for row in csv_reader
        src, dst = src_dst_hash(row)
        arc = read_leg!(counts, row, is_common_arc(row))
        added, ignore_type = add_arc!(network, src, dst, arc; verbose=verbose)
        added || (ignored[ignore_type] += 1)
        # if arc.carbonCost < EPS
        # println(row)
        # println(network.graph[src])
        # println(network.graph[dst])
        # println(arc)
        # @error "No carbon cost on this arc"
        # throw(ErrorException("No carbon cost on this arc"))
        # end
    end
    ignoredStr = join(pairs(ignored), ", ")
    @info "Read $(ne(network.graph)) legs : $counts" :ignored = ignoredStr
end

function bundle_hash(row::CSV.Row)
    return hash(row.supplier_account, hash(row.customer_account))
end

function order_hash(row::CSV.Row)
    return hash(row.delivery_time_step + 1, bundle_hash(row))
end

function com_size(row::CSV.Row)
    baseSize = min(round(Int, max(10, row.size * 100)), SEA_CAPACITY)
    # if baseSize > 0.5 * SEA_CAPACITY
    #     return baseSize
    # elseif baseSize > 0.25 * SEA_CAPACITY
    #     return min(SEA_CAPACITY, baseSize * 2)
    # elseif baseSize > 0.1 * SEA_CAPACITY
    #     return min(SEA_CAPACITY, baseSize * 3)
    # elseif baseSize > 0.05 * SEA_CAPACITY
    #     return min(SEA_CAPACITY, baseSize * 4)
    # elseif baseSize > 0.025 * SEA_CAPACITY
    #     return min(SEA_CAPACITY, baseSize * 5)
    # elseif baseSize > 0.01 * SEA_CAPACITY
    #     return min(SEA_CAPACITY, baseSize * 6)
    # end
    # return min(SEA_CAPACITY, baseSize * 7)
    return baseSize
end

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

# Vectors starts at index 0 in Python so adding 1 to get the right index in Julia
function get_order!(orders::Dict{UInt,Order}, row::CSV.Row, bundle::Bundle)
    return get!(orders, order_hash(row), Order(bundle, row.delivery_time_step + 1))
end

function add_date!(dateHorizon::Vector{String}, row::CSV.Row)
    dateIdx = row.delivery_time_step + 1
    if length(dateHorizon) < dateIdx
        append!(dateHorizon, ["" for _ in 1:(dateIdx - length(dateHorizon))])
    end
    if dateHorizon[dateIdx] == ""
        dateHorizon[dateIdx] = row.delivery_date
    end
end

function read_commodities(networkGraph::NetworkGraph, commodities_file::String)
    orders, bundles = Dict{UInt,Order}(), Dict{UInt,Bundle}()
    dates, partNums = Vector{String}(), Dict{UInt,String}()
    comCount, comUnique = 0, 0
    # Reading .csv file
    csv_reader = CSV.File(
        commodities_file;
        types=Dict(
            "supplier_account" => String,
            "customer_account" => String,
            "delivery_date" => String,
        ),
    )
    @info "Reading commodity orders from CSV file $(basename(commodities_file)) ($(length(csv_reader)) lines)"
    # Creating objects : each line is a commodity order
    for row in csv_reader
        # Getting bundle, order and commodity data
        bundle = get_bundle!(bundles, row, networkGraph)
        bundle === nothing && continue
        order = get_order!(orders, row, bundle)
        # If the order is new (no commodities) we have to add it to the bundle
        length(order.content) == 0 && push!(bundle.orders, order)
        # Creating (and Duplicating) commodity
        partNumHash = hash(row.part_number)
        partNums[partNumHash] = row.part_number
        commodity = Commodity(order.hash, partNumHash, com_size(row), row.lead_time_cost)
        rowQuantity = round(Int, row.quantity)
        # if rowQuantity < 3
        #     rowQuantity *= 5
        # elseif rowQuantity < 5
        #     rowQuantity *= 4
        # elseif rowQuantity < 10
        #     rowQuantity *= 3
        # elseif rowQuantity < 20
        #     rowQuantity *= 2
        # end
        append!(order.content, [commodity for _ in 1:(rowQuantity)])
        comCount += rowQuantity
        comUnique += 1
        # Is it a new time step ?
        add_date!(dates, row)
    end
    # Transforming dictionnaries into vectors (sorting the vector so that the idx field correspond to the actual idx in the vector)
    bundleVector = sort(collect(values(bundles)); by=bundle -> bundle.idx)
    @info "Read $(length(bundles)) bundles, $(length(orders)) orders and $comCount commodities ($comUnique without quantities) on a $(length(dates)) steps time horizon"
    return bundleVector, dates, partNums
end

function read_instance(node_file::String, leg_file::String, commodities_file::String)
    networkGraph = NetworkGraph()
    read_and_add_nodes!(networkGraph, node_file)
    read_and_add_legs!(networkGraph, leg_file)
    # Adding general properties 
    seaTime, seaNumber, maxLeg = 0, 0, 0
    netGraph = networkGraph.graph
    for (srcHash, dstHash) in edge_labels(netGraph)
        if netGraph[srcHash, dstHash].type == :oversea
            seaTime += netGraph[srcHash, dstHash].travelTime
            seaNumber += 1
        end
        maxLeg = max(maxLeg, netGraph[srcHash, dstHash].travelTime)
    end
    meanOverseaTime = seaNumber == 0 ? 0 : round(Int, seaTime / seaNumber)
    netGraph[][:meanOverseaTime] = meanOverseaTime
    netGraph[][:maxLeg] = maxLeg
    bundles, dates, partNums = read_commodities(networkGraph, commodities_file)
    return Instance(
        networkGraph,
        TravelTimeGraph(),
        TimeSpaceGraph(),
        bundles,
        length(dates),
        dates,
        partNums,
    )
end