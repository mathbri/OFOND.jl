# Graph to store all metadatas of the actual network

# Network Node Data
struct NetworkNode
    # Defining properties
    account::String      # account number of the node
    type::Symbol         # node type
    hash::UInt
    # Informations
    name::String         # name of the node
    coordinates::LLA     # coordinates of the node expressed in (lat*100, lon*100)
    country::String      # country the node is located in
    continent::String    # continent the node is located in
    # Network properties
    isCommon::Bool
    # Costs
    volumeCost::Float64  # cost of routing a m3 through this node

    function NetworkNode(
        account::String,
        type::Symbol,
        name::String,
        coordinates::LLA,
        country::String,
        continent::String,
        isCommon::Bool,
        volumeCost::Float64,
    )
        return new(
            account,
            type,
            hash(account, hash(type)),
            name,
            coordinates,
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

# Network Graph
struct NetworkGraph
    graph::MetaGraph
end

function Base.:(==)(node1::NetworkNode, node2::NetworkNode)
    return (node1.account == node2.account) && (node1.type == node2.type)
end

function Base.hash(node::NetworkNode)
    return hash(node.account, hash(node.type))
end

function Base.show(node::NetworkNode)
    # TODO : implement function
end

# Copy a node information and only change the node type
function change_node_type(node::NetworkNode, newType::Symbol)
    return NetworkNode(
        node.account,
        newType,
        node.name,
        node.coordinates,
        node.country,
        node.continent,
        node.isCommon,
        node.volumeCost,
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
function add_node!(network::NetworkGraph, node::NetworkNode)
    if haskey(network.graph, node.hash)
        @warn "Same node already in the network" :node = network[node.hash]
    end
    # Adding the node to the network graph
    network.graph[node.hash] = node
    # If the node is a port, loading port point added so adding destination port point also
    if node.type == :port_l
        newNode = change_node_type(node, :port_d)
        network.graph[newNode.hash] = newNode
    end
    # If its a supplier adding shortcut arc to the network 
    if src.type == :supplier
        arc = NetworkArc(:shortcut, EPS, 1, false, EPS, false, EPS, 1_000_000)
        add_arc!(network, src, src, arc)
    end
end

# Adding a leg to the network
function add_arc!(
    network::NetworkGraph, src::NetworkNode, dst::NetworkNode, arc::NetworkArc
)
    if haskey(network.graph, src.hash, dst.hash)
        @warn "Source and destination already have arc data" :source = network[src.hash] :destination = network[hash(
            dst
        )]
    end
    if !haskey(network.graph, src.hash)
        @warn "Source unknown in the network" :source = network[src.hash]
    end
    if !haskey(network.graph, dst.hash)
        @warn "Destination unknown in the network" :destination = network[dst.hash]
    end
    # Adding the leg to the network graph
    return network.graph[src.hash, dst.hash] = arc
end