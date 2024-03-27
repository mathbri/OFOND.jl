# File containing all functions to read an instance

function check_node_type(nodeType::Symbol, counts::Dict{Symbol, Int})
    if !(nodeType in NODE_TYPES) 
        @warn "Node type not in NodeTypes" :nodeType=nodeType
    else
        counts[nodeType] += 1
    end
end

function read_and_add_nodes!(networkGraph::NetworkGraph, node_file::String)
    counts = Dict{Symbol, Int}(:supplier => 0, :plant => 0, :xdock => 0, :iln => 0, :port_l => 0, :port_d => 0)
    # Reading .csv file
    csv_reader = CSV.File(node_file, types = Dict("point_account" => String15, "point_type" => String15))
    println("Reading nodes from CSV file $(node_file) ($(length(csv_reader)) lines)")
    for (i, row) in enumerate(csv_reader)
        nodeType = Symbol(row.point_type)
        check_node_type(nodeType, counts)
        node = NetworkNode(row.point_account,
                           nodeType,
                           row.point_name,
                           LLA(row.point_latitude, row.point_longitude),
                           row.point_country, 
                           row.point_continent,
                           nodeType in COMMON_NODE_TYPES, 
                           row.point_m3_cost)
        add_node!(networkGraph, node)
    end
    println("Read $(nv(networkGraph)) nodes : $counts \n")
end

function check_arc_type(arcType::Symbol, counts::Dict{Symbol, Int})
    if !(arcType in ARC_TYPES) 
        @warn "Arc type not in ArcTypes" :arcType=arcType
    else
        counts[arcType] += 1
    end
end

function get_network_node(networkGraph::NetworkGraph, account::String, type::String)
    nodeType = Symbol(type)
    nodeHash = hash(account, nodeType)
    return networkGraph[nodeHash]
end

function read_and_add_legs!(networkGraph::NetworkGraph, leg_file::String)
    counts = Dict{Symbol, Int}(:direct => 0, :outsource => 0, :delivery => 0, :cross_plat => 0, :oversea => 0, :port_transport => 0)
    # Reading .csv file
    csv_reader = CSV.File(leg_file, types = Dict("source_account" => String15, "destination_account" => String15, "source_type" => String15, "destination_type" => String15, "leg_type" => String15))
    println("Reading legs from CSV file $(file_name) ($(length(csv_reader)) lines)")
    for (i, row) in enumerate(csv_reader)
        arcType = Symbol(row.leg_type)
        check_arc_type(arcType, counts)
        sourceNode = get_network_node(networkGraph, row.source_account, row.source_type)
        destNode = get_network_node(networkGraph, row.destination_account, row.destination_type)
        arc = NetworkArc(arcType,
                         row.distance,
                         floor(Int, row.travel_time),
                         sourceNode.isCommon && destNode.isCommon,
                         row.unitCost,
                         row.isLinear,
                         row.carbonCost,
                         row.capacity)
    end
    println("Read $(ne(networkGraph)) legs : $counts \n")
end

function read_commodities(networkGraph::NetworkGraph, commodities_file::String)
    orders = Dict{UInt, Order}()
    bundles = Dict{UInt, Bundle}()
    comCount = 0
    allDates = Set{Date}()
    # Reading .csv file
    csv_reader = CSV.File(commodities_file, types=Dict("supplier_account" => String15, "customer_account" => String))
    println("Reading commodity orders from CSV file $(file_name) ($(length(csv_reader)) lines)")
    # Creating objects : each line is a commodity order
    println("Creating initial objects...")
    for (i, row) in enumerate(csv_reader)
        supplierNode = networkGraph[hash(row.supplier_account, :supplier)]
        customerNode = networkGraph[hash(row.customer_account, :plant)]
        # Getting bundle and order
        bundle = get!(bundles, hash(row.supplier_account, hash(row.customer_account)), Bundle(supplierNode, customerNode, Order[]))
        orderKey = hash(row.supplier_account, hash(row.customer_account, hash(row.delivery_time_step)))
        order = get!(orders, orderKey, Order(bundle, row.delivery_time_step, Commodity[]))
        # If the order is new we have to add it to the bundle
        if !haskey(orders, orderKey) 
            push!(bundle.orders, order) 
        end
        # Creating commodity (to be duplicated)
        commodity = Commodity(order, row.part_number, round(Int, max(1, row.size*100)), row.lead_time_cost)
        # Duplicating commodity by quantity
        append!(order.content, [commodity for _ in 1:row.quantity])
        comCount += row.quantity
        # Is it a new time step ?
        deliveryDate = Date(row.delivery_date)
        push!(allDates, deliveryDate)
    end
    bundleVector = collect(values(bundles))
    # Ordering the time horizon
    dateHorizon = sort(collect(allDates))
    println("Read $(length(bundles)) bundles, $(length(orders)) orders and $comCount commodities " * 
            "on a $(length(dateHorizon)) steps time horizon\n")
    return bundleVector, dateHorizon
end

function read_instance(node_file::String, leg_file::String, commodities_file::String)
    networkGraph = NetworkGraph()
    read_and_add_nodes!(networkGraph, node_file)
    read_and_add_legs!(networkGraph, leg_file) 
    bundles, dateHorizon = read_commodities(networkGraph, commodities_file)
    return Instance(networkGraph, bundles, length(dateHorizon), dateHorizon)
end