# Graph to store all metadatas of the actual network

# Network Node Data
struct NetworkNode
    # Defining properties
    account :: String               # account number of the node
    type :: UInt                    # node type
    # Informations
    name :: String                  # name of the node
    coordinates :: Tuple{Int, Int}  # coordinates of the node expressed in (lat*100, lon*100)
    country :: String               # country the node is located in
    continent :: String             # continent the node is located in
    # Network properties
    isCommon :: Bool
    # Costs
    volumeCost :: Float64           # cost of routing a m3 through this node
end

# Network Arc Data 
struct NetworkArc
    # Informations
    type :: UInt         # type of arc
    distance :: Float64  # distance in km 
    travelTime :: Int    # time step taken to use the arc
    isCommon :: Bool         
    # Transportation Costs
    unitCost :: Float64  # cost of routing a transport unit on this arc
    isLinear :: Bool     # is it linear cost or bin-packing cost 
    carbonCost :: Float64  # co2 cost induced by (fully-loaded) transport units
    # Load
    capacity :: Int      # container capacity on this arc
end

# Network Graph
struct NetworkGraph
    graph :: MetaGraph
end

function Base.:(==)(node1::NetworkNode, node2::NetworkNode)
    return (node1.account == node2.account) && (node1.type == node2.type)
end

function Base.hash(node::NetworkNode)
    return hash(node.account, node.type)
end

function Base.show(node::NetworkNode)
    # TODO : implement function
end

# Copy a node information and only change the node type
function change_node_type(node::NetworkNode, newType::UInt)
    return NetworkNode(node.account, newType, node.name, node.coordinates, node.country, node.continent, node.isCommon, node.volumeCost)
end

# Initializing empty network graph
function NetworkGraph()
    network = MetaGraph(
        DiGraph();
        label_type = UInt,
        vertex_data_type = NetworkNode,
        edge_data_type = NetworkArc,
        graph_data=nothing,
    )
    return NetworkGraph(network)
end

# TODO : transformation of csv data to struct is to be done in the reading file
# Adding a node to the network
function add_node!(network::NetworkGraph, node::NetworkNode)
    if haskey(network, hash(node))
        @warn "Same node already in the network" :node=network[hash(node)]
    end
    # Adding the node to the network graph
    network[hash(node)] = node
    # If the node is a port, loading port point added so adding destination port point also
    if nodeType == PORT_L
        newNode = change_node_type(node, PORT_D)
        network[hash(newNode)] = newNode
    end
end

# TODO : transformation of csv data to struct is to be done in the reading file
# Adding a leg to the network
function add_arc!(network::NetworkGraph, source::NetworkNode, destination::NetworkNode, arc::NetworkArc)
    if haskey(network, hash(source), hash(destination))
        @warn "Source and destination already have arc data" :source=network[hash(source)] :destination=network[hash(destination)]
    end
    if !haskey(network, hash(source))
        @warn "Source unknown in the network" :source=network[hash(source)]
    end
    if !haskey(network, hash(destination))
        @warn "Destination unknown in the network" :destination=network[hash(destination)]
    end
    # Adding the leg to the network graph
    network[hash(source), hash(destination)] = arc
end 