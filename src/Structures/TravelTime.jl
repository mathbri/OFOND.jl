# Graph structure used to compute bundle paths 

# TODO : change name to delivery graph to avoid confusion with arc travel times ?

# Travel Time Graph
struct TravelTimeGraph
    # Core fields
    graph::SimpleDiGraph # graph structure
    networkNodes::Vector{NetworkNode} # nodes data
    networkArcs::SparseMatrixCSC{NetworkArc,Int} # arcs data 
    stepToDel::Vector{Int} # nodes time step until delivery step
    # Properties
    costMatrix::SparseMatrixCSC{Float64,Int} # cost matrix used for path computation
    commonNodes::Vector{Int} # common nodes of the graph
    bundleStartNodes::Vector{Int} # start nodes for bundles
    bundleEndNodes::Vector{Int} # end nodes for bundles
    hashToIdx::Dict{UInt,Int} # dict to easily recover nodes from time space to travel time
end

function TravelTimeGraph()
    return TravelTimeGraph(
        SimpleDiGraph(),
        NetworkNode[],
        SparseMatrixCSC{NetworkArc,Int}(),
        Int[],
        sparse(zeros(Float64, 0, 0)),
        Int[],
        Int[],
        Int[],
        Dict{UInt,Int}(),
    )
end

function TravelTimeGraph(
    travelTimeGraph::TravelTimeGraph,
    I::Vector{Int},
    J::Vector{Int},
    arcs::Vector{NetworkArc},
    costs::Vector{Float64},
)
    return TravelTimeGraph(
        travelTimeGraph.graph,
        travelTimeGraph.networkNodes,
        sparse(I, J, arcs),
        travelTimeGraph.stepToDel,
        sparse(I, J, costs),
        travelTimeUtils.commonNodes,
        travelTimeUtils.bundleStartNodes,
        travelTimeUtils.bundleEndNodes,
        travelTimeUtils.bundleOnNodes,
    )
end

# Methods

function get_bundle_on_nodes(bundles::Vector{Bundle})
    bundlesOnNodes = Dict{UInt,Vector{Bundle}}()
    for bundle in bundles
        supplierBundles = get!(bundlesOnNodes, bundle.supplier.hash, Bundle[])
        push!(supplierBundles, bundle)
        customerBundles = get!(bundlesOnNodes, bundle.customer.hash, Bundle[])
        push!(customerBundles, bundle)
    end
    return bundlesOnNodes
end

function get_node_extra_copies(
    nodeData::NetworkNode, bundlesOnSupplier::Dict{UInt,Vector{Bundle}}, maxTime::Int
)
    if nodeData.type == :plant
        return 0
    elseif nodeData.type == :supplier
        return maximum(bundle -> bundle.maxDelTime, bundlesOnSupplier[nodeHash]) - 1
    else
        return maxTime - 1
    end
end

function add_timed_node!(
    travelTimeGraph::TravelTimeGraph, nodeData::NetworkNode, stepToDel::Int
)
    add_vertex!(travelTimeGraph.graph)
    push!(travelTimeGraph.networkNodes, nodeData)
    return push!(travelTimeGraph.stepToDel, stepToDel)
end

function add_timed_supplier!(
    travelTimeGraph::TravelTimeGraph,
    nodeData::NetworkNode,
    stepToDel::Int,
    bundlesOnSupplier::Dict{UInt,Vector{Bundle}},
)
    add_timed_node!(travelTimeGraph, nodeData, stepToDel)
    nodeIdx = nv(travelTimeGraph.graph)
    startOnNode = filter(
        bundle -> bundle.maxDelTime == stepToDel, bundlesOnSupplier[nodeData.hash]
    )
    for bundle in startOnNode
        travelTimeGraph.bundleStartNodes[bundle.idx] = nodeIdx
    end
    return travelTimeGraph.hashToIdx[hash(stepToDel, nodeData.hash)] = nodeIdx
end

function add_timed_customer!(
    travelTimeGraph::TravelTimeGraph,
    nodeData::NetworkNode,
    stepToDel::Int,
    bundlesOnCustomer::Dict{UInt,Vector{Bundle}},
)
    add_timed_node!(travelTimeGraph, nodeData, stepToDel)
    nodeIdx = nv(travelTimeGraph.graph)
    for (h, bundle) in bundlesOnCustomer
        travelTimeGraph.bundleEndNodes[bundle.idx] = nodeIdx
    end
end

function add_timed_platform!(
    travelTimeGraph::TravelTimeGraph, nodeData::NetworkNode, stepToDel::Int
)
    add_timed_node!(travelTimeGraph, nodeData, stepToDel)
    return push!(travelTimeGraph.commonNodes, nv(travelTimeGraph.graph))
end

function add_network_node!(
    travelTimeGraph::TravelTimeGraph,
    nodeData::NetworkNode,
    bundlesOnNodes::Dict{UInt,Vector{Bundle}},
)
    # Computing the number of times we have to add a timed copy of the node 
    # plant = 0, suppliers = max of bundle del time, platforms = overall max del time
    maxTime = maximum(
        bundles -> maximum(bundle -> bundle.maxDelTime, bundles), values(bundlesOnNodes)
    )
    nodeExtraCopies = get_node_extra_copies(nodeData, bundlesOnNodes, maxTime)
    for stepToDel in 0:nodeExtraCopies
        if nodeData.type == :supplier
            add_timed_supplier!(travelTimeGraph, nodeData, stepToDel, bundlesOnNodes)
        elseif nodeData.type == :plant
            add_timed_customer!(travelTimeGraph, nodeData, stepToDel, bundlesOnNodes)
        else
            add_timed_platform!(travelTimeGraph, nodeData, stepToDel)
        end
    end
end

function add_network_arc!(
    travelTimeGraph::TravelTimeGraph,
    srcData::NetworkNode,
    dstData::NetworkNode,
    arcData::NetworkArc,
)
    maxTime = maximum(travelTimeGraph.stepToDel)
    for stepToDel in 0:maxTime
        # Adding timed copy of network arc
        src = get(travelTimeGraph.hashToIdx, hash(stepToDel, srcData.hash), nothing)
        dst = get(
            travelTimeGraph.hashToIdx,
            hash(stepToDel - arcData.travelTime, dstData.hash),
            nothing,
        )
        if src !== nothing && dst !== nothing
            add_edge!(travelTimeGraph.graph, src, dst)
        end
    end
end

function add_arc_to_vectors!(
    vectors::Tuple{Vector{Int},Vector{Int},Vector{NetworkArc},Vector{Float64}},
    travelTimeGraph::TravelTimeGraph,
    srcData::NetworkNode,
    dstData::NetworkNode,
    arcData::NetworkArc,
)
    maxTime = maximum(travelTimeGraph.stepToDel)
    for stepToDel in 0:maxTime
        # Adding timed copy of network arc
        src = get(travelTimeGraph.hashToIdx, hash(stepToDel, srcData.hash), nothing)
        dst = get(
            travelTimeGraph.hashToIdx,
            hash(stepToDel - arcData.travelTime, dstData.hash),
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

function TravelTimeGraph(network::NetworkGraph, bundles::Vector{Bundle})
    # Computing for each node which bundles starts and which bundles end at this node 
    bundlesOnNodes = get_bundle_on_nodes(bundles)
    maxTime = maximum(bundle -> bundle.maxDelTime, bundles)
    # Initializing structure
    travelTimeGraph = TravelTimeGraph()
    # Adding all nodes from the network graph
    for nodeHash in labels(network)
        add_network_node!(travelTimeGraph, network[nodeHash], bundlesOnNodes)
    end
    # Initializing vectors for sparse matrices
    I, J, arcs, costs = Int[], Int[], NetworkArc[], Float64[]
    # Adding all arcs form the network graph
    for (srcHash, dstHash) in edge_labels(network)
        srcData, dstData, arcData = network[srcHash],
        network[dstHash],
        network[srcHash, dstHash]
        add_network_arc!(travelTimeGraph, srcData, dstData, arcData)
        add_arc_to_vectors!((I, J, arcs, costs), travelTimeGraph, srcData, dstData, arcData)
    end
    # Creating final structures (because of sparse matrices)
    return TravelTimeGraph(travelTimeGraph, I, J, arcs, costs)
end

function is_path_elementary(travelTimeGraph::TravelTimeGraph, path::Vector{Int})
    return is_path_elementary(hash.(travelTimeGraph.networkNodes[path]))
end