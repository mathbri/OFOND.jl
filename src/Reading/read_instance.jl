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

function read_commodities(commodities_file::String)

end

function read_instance(node_file::String)
    networkGraph = NetworkGraph()
    read_and_add_nodes!(networkGraph, node_file)
    # read legs 
    # add legs 
    # read commodities
end