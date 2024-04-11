# Time Space Graph structure for solution representation 

# Time Space Graph
struct TimeSpaceGraph
    # Core fields
    graph::SimpleDiGraph # graph structure
    timeHorizon::Int # number of steps in the time horizon
    networkNodes::Vector{NetworkNode} # nodes data
    timeStep::Vector{Int} # time steps for each node
    networkArcs::SparseMatrixCSC{NetworkArc,Int} # arcs data
    # Properties
    hashToIdx::Dict{UInt,Int}                # dict to easily recover nodes from travel time to time space
    currentCost::SparseMatrixCSC{Float64,Int}   # used by slope scaling
    commonArcs::Vector{Edge} # common arcs of the graph
end

function TimeSpaceGraph(timeHorizon::Int)
    return TimeSpaceGraph(
        DiGraph(),
        timeHorizon,
        NetworkNode[],
        Int[],
        SparseMatrixCSC{NetworkArc,Int}(),
        Dict{UInt,Int}(),
        sparse(zeros(Float64, 0, 0)),
        Edge[],
    )
end

function TimeSpaceGraph()
    return TimeSpaceGraph(0)
end

function TimeSpaceGraph(
    timeSpaceGraph::TimeSpaceGraph,
    I::Vector{Int},
    J::Vector{Int},
    arcs::Vector{NetworkArc},
    costs::Vector{Float64},
)
    return TimeSpaceGraph(
        timeSpaceGraph.graph,
        timeSpaceGraph.timeHorizon,
        timeSpaceGraph.networkNodes,
        timeSpaceGraph.timeStep,
        sparse(I, J, arcs),
        timeSpaceGraph.hashToIdx,
        sparse(I, J, costs),
        timeSpaceGraph.commonArcs,
    )
end

# Methods

function add_network_node!(timeSpaceGraph::TimeSpaceGraph, node::NetworkNode)
    # Adding a timed copy for each time step 
    for timeStep in 1:(timeSpaceGraph.timeHorizon)
        # Adding timed copy to the graph
        add_vertex!(timeSpaceGraph.graph)
        push!(timeSpaceGraph.networkNodes, node)
        push!(timeSpaceGraph.timeStep, timeStep)
        timeSpaceGraph.hashToIdx[hash(timeStep, node.hash)] = nv(timeSpaceGraph.graph)
    end
end

function add_network_arc!(
    timeSpaceGraph::TimeSpaceGraph,
    srcData::NetworkNode,
    dstData::NetworkNode,
    arcData::NetworkArc,
)
    for timeStep in 1:(timeSpaceGraph.timeHorizon)
        # Adding timed copy of network arc
        src = get(timeSpaceGraph.hashToIdx, hash(timeStep, srcData.hash), nothing)
        dst = get(
            timeSpaceGraph.hashToIdx,
            hash(timeStep + arcData.travelTime, dstData.hash),
            nothing,
        )
        if src !== nothing && dst !== nothing
            add_edge!(timeSpaceGraph.graph, src, dst)
        end
    end
end

function add_arc_to_vectors!(
    vectors::Tuple{Vector{Int},Vector{Int},Vector{NetworkArc},Vector{Float64}},
    timeSpaceGraph::TimeSpaceGraph,
    srcData::NetworkNode,
    dstData::NetworkNode,
    arcData::NetworkArc,
)
    for timeStep in 1:(timeSpaceGraph.timeHorizon)
        # Adding timed copy of network arc
        src = get(travelTimeGraph.hashToIdx, hash(timeStep, srcData.hash), nothing)
        dst = get(
            travelTimeGraph.hashToIdx,
            hash(timeStep + arcData.travelTime, dstData.hash),
            nothing,
        )
        if src !== nothing && dst !== nothing
            I, J, arcs, costs = vectors
            push!(I, src)
            push!(J, dst)
            push!(arcs, arcData)
            push!(costs, EPS)
        end
    end
end

function TimeSpaceGraph(network::NetworkGraph, timeHorizon::Int)
    # Initializing structures
    timeSpaceGraph = TimeSpaceGraph()
    # Adding all nodes from the network graph
    for nodeHash in labels(network)
        add_network_node!(timeSpaceGraph, network[nodeHash])
    end
    # Initializing vectors for sparse matrices
    I, J, arcs, costs = Int[], Int[], NetworkArc[], Float64[]
    nodesHash = hash.(timeSpaceGraph.networkNodes)
    # Adding all arcs form the network graph (except shortcuts)
    for (sourceHash, destHash) in edge_labels(network)
        srcData, dstData, arcData = network[srcHash],
        network[dstHash],
        network[srcHash, dstHash]
        # Not adding shortcut arcs 
        arcData.type == :shortcut && continue
        add_network_arc!(timeSpaceGraph, srcData, dstData, arcData)
        add_arc_to_vectors!((I, J, arcs, costs), timeSpaceGraph, srcData, dstData, arcData)
    end
    return TimeSpaceGraph(timeSpaceGraph, I, J, arcs, costs)
end

function is_path_elementary(timeSpaceGraph::TimeSpaceGraph, path::Vector{Int})
    return is_path_elementary(hash.(timeSpaceGraph.networkNodes[path]))
end
