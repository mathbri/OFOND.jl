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
    # Transport Costs
    unitCost :: Float64  # cost of routing a transport unit on this arc 
    # Load
    isLinear :: Bool     # is it linear cost or bin-packing cost 
    capacity :: Int      # container capacity on this arc
end

function Base.:(==)(node1::NetworkNode, node2::NetworkNode)
    return (node1.account == node2.account) && (node1.type == node2.type)
end

function Base.hash(node::NetworkNode)
    return hash(node.account, node.type)
end

# TODO : shallow copy fields that did not change
# Copy a node information and only change the node type
function change_node_type(node::NetworkNode, newType::UInt)
    return NetworkNode(node.account, newType, node.name, node.coordinates, node.country, node.continent, node.isCommon, node.volumeCost)
end

# Initializing empty network graph
function initialize_network()
    network = MetaGraph(
        DiGraph();
        label_type = UInt,
        vertex_data_type = NetworkNode,
        edge_data_type = NetworkArc,
        graph_data=nothing,
    )
    return network
end

# TODO : transformation of csv data to struct is to be done in the reading file
# Adding a node to the network
function add_node!(network::MetaGraph, node::NetworkNode)
    # TODO : add warning if duplicate node found
    # Adding the node to the network graph
    network[hash(node)] = node
    # If the node is a port, loading port point added so adding destination port point also
    if nodeType == PORT_L
        newNode = change_node_type(node, PORT_D)
        network[hash(newNode)] = newNode
    end
    # TODO : if the node is a platform or a plant, add a corresponding supplier node with a free arc to the original node
end

# TODO : transformation of csv data to struct is to be done in the reading file
# Adding a leg to the network
function add_leg!(network::MetaGraph, source::NetworkNode, destination::NetworkNode, arc::NetworkArc)
    # TODO : add warning if same source and destination
    # TODO : add warning if source or destination is unknown 
    # Adding the leg to the network graph
    network[hash(source), hash(destination)] = arc
end