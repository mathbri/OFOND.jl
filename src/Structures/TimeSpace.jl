# Time Space Graph structure for solution representation 

# Time Space Graph
struct TimeSpaceGraph
    graph :: DiGraph
    timeHorizon :: Int
    networkNodes :: Vector{NetworkNode}
    timeSteps :: Vector{Int}
    networkArcs :: SparseMatrixCSC{NetworkArc, Int}
    bins :: SparseMatrixCSC{Vector{Bin}, Int}
    travelTimeLink :: Dict{UInt, Int}                # dict to easily recover nodes from travel time to time space
end

struct TimeSpaceUtils
    currentCost :: SparseMatrixCSC{Float64, Int}   # used by slope scaling
    binLoads :: SparseMatrixCSC{Vector{Int}, Int}  # bin loads on this arc (used for fastier computation)
end

# TODO : put all major block in functions
function build_time_space_and_utils(network::NetworkGraph, timeHorizon::Int)
    # Initializing structures
    timeSpaceGraph = TimeSpaceGraph(DiGraph(), timeHorizon, NetworkNode[], Int[], sparse(zeros(Int, 0, 0)), sparse(zeros(Int, 0, 0)), Dict{UInt, Int}())
    timeSpaceUtils = TimeSpaceUtils(sparse(zeros(Float64, 0, 0)), sparse(zeros(Int, 0, 0)))
    # Adding all nodes from the network graph
    for nodeHash in labels(network)
        nodeData = network[nodeHash]
        # Adding a timed copy for each time step 
        for timeStep in 1:timeHorizon
            # Adding timed copy to the graph
            add_vertex!(timeSpaceGraph.graph)
            push!(timeSpaceGraph.networkNodes, nodeData)
            push!(timeSpaceGraph.timeSteps, timeStep)
            timeSpaceGraph.travelTimeLink[hash(timeStep, hash(nodeData))] = nv(timeSpaceGraph.graph)
        end
    end
    # Initializing vectors for sparse matrices
    I, J = Int[], Int[]
    arcs, bins, costs, loads = NetworkArc[], Vector{Vector{Bin}}(), Float64[], Vector{Vector{Int}}()
    nodesHash = hash.(timeSpaceGraph.networkNodes)
    # Adding all arcs form the network graph
    for (sourceHash, destHash) in edge_labels(network)
        arcData = network[sourceHash, destHash]
        # I get all source node copies and dest node copies (via hash)
        sourceNodeIdxs = findall(nodeHash -> nodeHash == sourceHash, nodesHash)
        destNodeIdxs = findall(nodeHash -> nodeHash == destHash, nodesHash)
        # I add an arc when source step to del - arc travel time = dest step to del
        for sourceNodeIdx in sourceNodeIdxs, destNodeIdx in destNodeIdxs
            if timeSpaceGraph.stepToDel[sourceNodeIdx] - arcData.travelTime == timeSpaceGraph.stepToDel[destNodeIdx]
                push!(I, sourceNodeIdx)
                push!(J, destNodeIdx)
                push!(arcs, arcData)
                push!(costs, EPS)
                push!(loads, Int[])
                push!(bins, Bin[])
            end
        end
    end
    # Building sparse matrix
    arcMatrix = sparse(I, J, arcs)
    costMatrix = sparse(I, J, costs)
    loadMatrix = sparse(I, J, loads)
    binMatrix = sparse(I, J, bins)
    # Creating final structures
    finalTimeSPace = TimeSpaceGraph(timeSpaceGraph.graph, timeSpaceGraph.timeHorizon, timeSpaceGraph.networkNodes, timeSpaceGraph.timeSteps, arcMatrix, binMatrix, timeSpaceGraph.travelTimeLink)
    finalTimeSpaceUtils = TimeSpaceUtils(costMatrix, loadMatrix)
    return finalTimeSPace, finalTimeSpaceUtils
end

# Project a node of the travel time graph on the time space graph for a specific delivery date 
function time_space_projector(travelTimeGraph::TravelTimeGraph, timeSpaceGraph::TimeSpaceGraph, travelTimeNode::Int, deliveryDate::Int)
    # Computing the time step from the delivery date and the steps from delivery
    timeSpaceDate = deliveryDate - travelTimeGraph.stepToDel[travelTimeNode]
    # If it goes out of the horizon, rolling it back to the top
    timeSpaceDate < 1 && timeSpaceDate += timeSpaceGraph.timeHorizon
    # Using travel time link dict to return the right node idx
    return timeSpaceGraph.travelTimeLink[
        hash(timeSpaceDate, hash(travelTimeGraph.networkNodes[travelTimeNode]))
    ]    
end

function is_path_elementary(path::Vector{UInt})
    if length(path) >= 4
        for (nodeIdx, nodeHash) in enumerate(path)
            if nodeHash in path[nodeIdx+1:end]
                # println("Non elementary path found : $path")
                return false
            end
        end
    end
    return true
end

# TODO : adapt from here

# Initialize empty time space graph
function TimeSpaceGraph(timeHorizon::Int, relaxed::Bool)
    arcTypeData = relaxed ? RelaxedTimedArc : TimedArc
    timeSpace = MetaGraph(
        DiGraph();
        label_type = UInt,
        vertex_data_type = TimeSpaceNode,
        edge_data_type = arcTypeData,
    )
    return TimeSpaceGraph(timeSpace, timeHorizon)
end

function build_time_extended_graph(network::MetaGraph, timeHorizon::Int) :: MetaGraph
    timeSpaceGraph = TimeSpaceGraph(timeHorizon)
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
        @assert arcData.travelTime < timeHorizon
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
