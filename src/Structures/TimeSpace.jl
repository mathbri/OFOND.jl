# Time Space Graph structure for solution representation 

# Time Space Node
struct TimeSpaceNode
    networkNode :: UInt  # network node hash corresponding
    timeStep :: Int      # time horizon step on which the node is located
end

# Time Space Arc (store container loads)
mutable struct TimeSpaceArc
    capacity :: Int        # bin capacity on this arc
    loads :: Vector{Int}   # bin loads on this arc (used for fastier computation)
    bins :: Vector{Bin}    # bins routed on this arc (actually used in solution)
end

# Time Space Graph
struct TimeSpaceGraph
    graph :: MetaGraph
    timeHorizon :: Int
end

function Base.:(==)(node1::TimeSpaceNode, node2::TimeSpaceNode)
    return (node1.networkNode == node2.networkNode) && (node1.timeStep == node2.timeStep)
end

# The idea is to have hash(timeStep, nodeHash)
function Base.hash(node::TimeSpaceNode)
    return hash(node.timeStep, node.networkNode)
end

# Initialize empty time space graph
function TimeSpaceGraph(timeHorizon::Int)
    timeSpace = MetaGraph(
        DiGraph();
        label_type = UInt,
        vertex_data_type = TimeSpaceNode,
        edge_data_type = TimeSpaceArc,
    )
    return TimeSpaceGraph(timeSpace, timeHorizon)
end

function build_time_extended_graph(network::MetaGraph, timeHorizon::Int) :: MetaGraph
    timeSpaceGraoh = TimeSpaceGraph(timeHorizon)
    println("Building time space graph...")
    # Adding every (node, time) pair to the graph
    for nodeHash in labels(network)
        nodeData = network[nodeHash] 
        for timeStep in 1:timeHorizon
            tsNode = TimeSpaceNode(nodeData.account, nodeData.type, timeStep)
            timeSpace[hash(tsNode)] = tsNode
            @assert hash(tsNode) == hash(timeStep, hash(nodeData))
        end
    end
    # Adding every timed edges to the graph
    for (sourceHash, destHash) in edge_labels(network)
        arcData = network[sourceHash, destHash]
        # Linking (node, t) with (node, t + travelTime) for every possible step
        for sourceStep in 1:timeHorizon
            tsSourceHash = hash(sourceStep, sourceHash)
            destStep = sourceStep + arcData.travelTime
            # Correcting step if it is out of the time horizon
            destStep = (destStep > T) ? (destStep % T) : destStep
            tsDestHash = hash(sourceStep + arcData.travelTime, destHash)
            tsArc = TimeSpaceArc(arcData.capacity, Int[], Bin[])
            timeSpace[ttSourceHash, ttDestHash] = tsArc
        end
    end
    return timeSpace
end
