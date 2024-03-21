# Graph structure used to compute bundle paths 

# TODO : change name to delivery graph to avoid confusion with arc travel times ?

# TODO : add field description
# Travel Time Graph
struct TravelTimeGraph
    graph :: DiGraph
    costMatrix :: SparseMatrixCSC{Int, Float64}
    networkNodes :: Vector{NetworkNode}
    networkArcs :: SparseMatrixCSC{Int, NetworkArc}
    timeSteps :: Vector{Int}
    commonNodes :: Vector{Int}
    maxDeliveryTime :: Int
    bundlesOnNode :: Vector{Vector{Bundle}}
end

# For networkNodes and networkArcs creation : pre-allocating memory (or pushing) stores only a shallow copy of objects 

# Methods

# TODO : adapt from here

# Initialize empty travel time graph
function TravelTimeGraph(maxDeliveryTime::Int)
    travelTimeGraph = MetaGraph(
        DiGraph();
        label_type = UInt,
        vertex_data_type = TravelTimeNode,
        edge_data_type = Float64,
        weight_function = identity,
    )
    return TravelTimeGraph(travelTimeGraph, maxDeliveryTime)
end

# Add node to the travel time graph
function add_node!(travelTimeGraph::TravelTimeGraph, node::TravelTimeNode)
    
end

# Add arc to the travel time graph
function add_arc!(travelTimeGraph::TravelTimeGraph, source::TravelTimeNode, destination::TravelTimeNode, cost::Float64)
    
end

# Create travel-time graph from network graph
function TravelTimeGraph(network::NetworkGraph)
    # Computing time horizon of the travel time graph
    maxDelTime = maximum(arcLabel -> network[arcLabel].travelTime, values(edge_labels(network)))
    # Buidling empty MetaGraph with only free legs (they will be updated for each bundle)
    travelTimeGraph = TravelTimeGraph(maxDelTime)
    println("Building travel time graph...")
    # Adding timed copies of nodes
    for nodeHash in labels(network)
        nodeData = network[nodeHash]
        for stepToDel in 0:maxDelTime
            # TODO : make shallow copy of nodeData data through a custom constructor
            ttNode = TravelTimeNode(nodeData.account, nodeData.type, stepToDel, nodeData.isCommon)
            travelTimeGraph[hash(ttNode)] = ttNode
            @assert hash(ttNode) == hash(stepToDel, hash(nodeData))
            # For plants, adding it only on the last time step
            if nodeData.type == PLANT; break end
        end
        # Adding shortcut legs between supplier copies t+1 -> t
        for (destStep, sourceStep) in partition(0:maxDelTime, 2, 1)
            sourceHash, destHash = hash(sourceStep, nodeHash), hash(destStep, nodeHash)
            travelTimeGraph[sourceHash, destHash] = EPS
        end
    end
    # Adding all legs 
    for (sourceHash, destHash) in edge_labels(network)
        arcData = network[sourceHash, destHash]
        # For delivery arcs, adding only to delivery step
        if arcData.type == DELIVERY
            ttSourceHash, ttDestHash = hash(0, sourceHash), hash(arcData.travelTime, destHash)
            travelTimeGraph[ttSourceHash, ttDestHash] = EPS
        end
        # Linking (node, t) with (node, t + travelTime) for every possible step
        for sourceStep in maxDelTime:-1:(1 + arcData.travelTime)
            ttSourceHash = hash(sourceStep, sourceHash)
            ttDestHash = hash(sourceStep + arcData.travelTime, destHash)
            travelTimeGraph[ttSourceHash, ttDestHash] = EPS
        end
    end
    return travelTimeGraph
end

# Extract common nodes list from the travel-time graph
function extract_common_nodes(travelTimeGraph::TravelTimeGraph)
    # Storing common nodes
    commonNodes = Int[]
    maxDelTime = travelTimeGraph[]
    # For each node, adding it to common nodes if it is common
    for nodeHash in labels(travelTimeGraph)
        nodeData = travelTimeGraph[nodeHash]
        # For points not tagged as common in the network, skipping
        if !(nodeData.isCommon); continue end
        # For common points, adding all their timed copies
        for stepToDel in 0:maxDelTime
            push!(travelTimeCommonNodes, code_for(hash(stepToDel, nodeHash)))
        end
    end
    return commonNodes
end

# Restrict the travel-time graph to a fixed amount of delivery steps (typically bundle.directArc.travelTime, + 1 for flexibility)
function restrict_bundle_travel_time(bundleGraph::TravelTimeGraph, maxDelTime::Int)
    nodesToExtract = Int[]
    # Adding timed copies of nodes from 0 to maxDelTime 
    for nodeHash in labels(bundleGraph)
        nodeData = bundleGraph[nodeHash]
        if nodeData.stepsToDelivery > maxDelTime; continue end
        # If the timed copy is within range, adding it to nodes extracted
        push!(nodesToExtract, code_for(nodeHash))
    end
    # Returning induced subgraph
    return induced_subgraph(bundleGraph, nodesToExtract)
end