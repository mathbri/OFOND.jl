# Graph to store all metadatas of the actual network

# Network Node Data
struct NetworkNode
    # Defining properties
    account::String      # account number of the node
    type::Symbol         # node type
    hash::UInt
    # Informations
    country::String      # country the node is located in
    continent::String    # continent the node is located in
    # Network properties
    isCommon::Bool
    # Costs
    volumeCost::Float64  # cost of routing a m3 through this node

    function NetworkNode(
        account::String,
        type::Symbol,
        country::String,
        continent::String,
        isCommon::Bool,
        volumeCost::Float64,
    )
        return new(
            account,
            type,
            hash(account, hash(type)),
            country,
            continent,
            isCommon,
            volumeCost,
        )
    end
end

# Network Arc Data 
struct NetworkArc
    # Informations
    type::Symbol         # type of arc
    distance::Float64    # distance in km 
    travelTime::Int      # time step taken to use the arc
    isCommon::Bool
    # Transportation Costs
    unitCost::Float64    # cost of routing a transport unit on this arc
    isLinear::Bool       # is it linear cost or bin-packing cost 
    carbonCost::Float64  # co2 cost induced by (fully-loaded) transport units
    # Load
    capacity::Int        # transport unit capacity
end

const SHORTCUT = NetworkArc(:shortcut, EPS, 1, false, EPS, false, EPS, 1_000_000)

# Network Graph
struct NetworkGraph
    graph::MetaGraph
end

function Base.:(==)(node1::NetworkNode, node2::NetworkNode)
    return (node1.account == node2.account) && (node1.type == node2.type)
end

function Base.hash(node::NetworkNode, h::UInt)
    return hash(node.account, hash(node.type, h))
end

# Copy a node information and only change the node type
function change_node_type(node::NetworkNode, newType::Symbol)
    return NetworkNode(
        node.account, newType, node.country, node.continent, node.isCommon, node.volumeCost
    )
end

# Initializing empty network graph
function NetworkGraph()
    network = MetaGraph(
        DiGraph();
        label_type=UInt,
        vertex_data_type=NetworkNode,
        edge_data_type=NetworkArc,
        graph_data=nothing,
    )
    return NetworkGraph(network)
end

# Adding a node to the network
function add_node!(network::NetworkGraph, node::NetworkNode; verbose::Bool=false)
    if haskey(network.graph, node.hash)
        verbose &&
            @warn "Same node already in the network" :nodeInGraph = network.graph[node.hash] :nodeToAdd =
                node
    elseif !(node.type in NODE_TYPES)
        verbose && @warn "Node type not in NodeTypes" :node = node :nodeTypes = join(
            NODE_TYPES, ", "
        )
    else
        # Adding the node to the network graph
        network.graph[node.hash] = node
        # If its a supplier adding shortcut arc to the network 
        node.type == :supplier && add_arc!(network, node, node, SHORTCUT)
        # Returning true if everything went well
        return true
    end
    # Returning false otherwise
end

# Adding a leg to the network
function add_arc!(network::NetworkGraph, src::UInt, dst::UInt, arc::NetworkArc)
    if haskey(network.graph, src, dst)
        @warn "Source and destination already have arc data" :srcInGraph = network.graph[src] :dstInGraph = network.graph[dst] :srcToAdd =
            src :dstToAdd = dst
    elseif !haskey(network.graph, src)
        @warn "Source unknown in the network" :source = src
    elseif !haskey(network.graph, dst)
        @warn "Destination unknown in the network" :destination = dst
    elseif !(arc.type in ARC_TYPES)
        @warn "Arc type not in ArcTypes" :arc = arc :arcTypes = join(ARC_TYPES, ", ")
    else
        # Adding the leg to the network graph (if no anomaly)
        network.graph[src, dst] = arc
    end
end

# Wrapper for network nodes
function add_arc!(
    network::NetworkGraph, src::NetworkNode, dst::NetworkNode, arc::NetworkArc
)
    # redifining warnings to give more information
    if haskey(network.graph, src.hash, dst.hash)
        @warn "Source and destination already have arc data" :srcInGraph = network.graph[src.hash] :dstInGraph = network.graph[dst.hash] :srcToAdd =
            src :dstToAdd = dst
    elseif !haskey(network.graph, src.hash)
        @warn "Source unknown in the network" :source = src
    elseif !haskey(network.graph, dst.hash)
        @warn "Destination unknown in the network" :destination = dst
    else
        return add_arc!(network, src.hash, dst.hash, arc)
    end
end

# TODO : add a function to change arc or node data if needed

# TODO : change zero function to return a constant value to optimize garbage collecting ?

function Base.zero(::Type{NetworkNode})
    return NetworkNode("0", :zero, "", "", false, 0.0)
end

# TODO : change from this to throw error ?
function Base.zero(::Type{NetworkArc})
    return NetworkArc(:zero, 0.0, 0, false, 0.0, false, 0.0, 0)
end

function Base.show(io::IO, node::NetworkNode)
    return print(io, "Node($(node.account), $(node.type))")
end

function is_node_in_country(networkGraph::NetworkGraph, node::Int, country::String)
    return networkGraph.graph[label_for(networkGraph.graph, node)].country == country
end

function is_node_in_continent(networkGraph::NetworkGraph, node::Int, continent::String)
    return networkGraph.graph[label_for(networkGraph.graph, node)].continent == continent
end

function is_node_in_continents(
    networkGraph::NetworkGraph, node::Int, continents::Vector{String}
)
    return networkGraph.graph[label_for(networkGraph.graph, node)].continent in continents
end