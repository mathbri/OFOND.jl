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

function get_bundle_on_supp_cust(bundles::Vector{Bundle})
    bundlesOnSupplier = Dict{UInt,Vector{Bundle}}()
    bundlesOnCustomer = Dict{UInt,Vector{Bundle}}()
    for bundle in bundles
        suppHash = hash(bundle.supplier)
        supplierBundles = get!(bundlesOnSupplier, suppHash, Int[])
        push!(supplierBundles, bundle)
        custHash = hash(bundle.customer)
        customerBundles = get!(bundlesOnCustomer, custHash, Int[])
        push!(customerBundles, bundle)
    end
    return bundlesOnSupplier, bundlesOnCustomer
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
    bundlesOnSupplier::Dict{UInt,Vector{Bundle}},
    bundlesOnCustomer::Dict{UInt,Vector{Bundle}},
    maxTime::Int,
)
    # Computing the number of times we have to add a timed copy of the node 
    # plant = 0, suppliers = max of bundle del time, platforms = overall max del time (done with init cond in max)
    nodeExtraCopies = get_node_extra_copies(nodeData, bundlesOnSupplier, maxTime)
    for stepToDel in 0:nodeExtraCopies
        if nodeData.type == :supplier
            add_timed_supplier!(travelTimeGraph, nodeData, stepToDel, bundlesOnSupplier)
        elseif nodeData.type == :plant
            add_timed_customer!(travelTimeGraph, nodeData, stepToDel, bundlesOnCustomer)
        else
            add_timed_platform!(travelTimeGraph, nodeData, stepToDel)
        end
    end
end

function add_arc_to_vectors!(
    vectors::Tuple{Vector{Int},Vector{Int},Vector{NetworkArc},Vector{Float64}},
    travelTimeGraph::TravelTimeGraph,
    sourceNodeIdx::Int,
    destNodeIdx::Int,
    arcData::NetworkArc,
)
    if travelTimeGraph.stepToDel[sourceNodeIdx] - arcData.travelTime ==
        travelTimeGraph.stepToDel[destNodeIdx]
        I, J, arcs, costs = vectors
        push!(I, sourceNodeIdx)
        push!(J, destNodeIdx)
        push!(arcs, arcData)
        push!(costs, EPS)
    end
end

function add_arc_and_shortcut!(
    vectors::Tuple{Vector{Int},Vector{Int},Vector{NetworkArc},Vector{Float64}},
    travelTimeGraph::TravelTimeGraph,
    sourceNodeIdxs::Vector{Int},
    destNodeIdxs::Vector{Int},
    arcData::NetworkArc,
)
    # I add an arc when source step to del - arc travel time = dest step to del
    for sourceNodeIdx in sourceNodeIdxs, destNodeIdx in destNodeIdxs
        add_arc_to_vectors!(vectors, travelTimeGraph, sourceNodeIdx, destNodeIdx, arcData)
    end
    # Also add shortcut
    arcData = NetworkArc(:shortcut, EPS, 1, false, 0.0, false, 0.0, 0)
    for sourceNodeIdx in sourceNodeIdxs, destNodeIdx in sourceNodeIdxs
        add_arc_to_vectors!(vectors, travelTimeGraph, sourceNodeIdx, destNodeIdx, arcData)
    end
end

# TODO : put all major block in functions
function TravelTimeGraph(network::NetworkGraph, bundles::Vector{Bundle})
    # Computing for each node which bundles starts and which bundles end at this node 
    bundlesOnSupplier, bundlesOnCustomer = get_bundle_on_supp_cust(bundles)
    maxTime = maximum(bundle -> bundle.maxDelTime, bundles)
    # Initializing structure
    travelTimeGraph = TravelTimeGraph()
    # Adding all nodes from the network graph
    for nodeHash in labels(network)
        nodeData = network[nodeHash]
        add_network_node!(
            travelTimeGraph, nodeData, bundlesOnSupplier, bundlesOnCustomer, maxTime
        )
    end
    # Initializing vectors for sparse matrices
    I, J, arcs, costs = Int[], Int[], NetworkArc[], Float64[]
    nodesHash = hash.(travelTimeGraph.networkNodes)
    # Adding all arcs form the network graph
    for (sourceHash, destHash) in edge_labels(network)
        arcData = network[sourceHash, destHash]
        # I get all source node copies and dest node copies (via hash)
        sourceNodeIdxs = findall(h -> h == sourceHash, nodesHash)
        destNodeIdxs = findall(h -> h == destHash, nodesHash)
        add_arc_and_shortcut!(
            (I, J, arcs, costs), travelTimeGraph, sourceNodeIdxs, destNodeIdxs, arcData
        )
    end
    # Creating final structures (because of sparse matrices)
    return TravelTimeGraph(travelTimeGraph, I, J, arcs, costs)
end

function is_path_elementary(path::Vector{UInt})
    if length(path) >= 4
        for (nodeIdx, nodeHash) in enumerate(path)
            if nodeHash in path[(nodeIdx + 1):end]
                # println("Non elementary path found : $path")
                return false
            end
        end
    end
    return true
end

# Project a node of the time space graph on the travel time graph for a specific bundle
# Returns a vector of travel-time node for corresponding orders in the bundle, -1 of no corresponding node for the order
# function travel_time_projector(
#     travelTimeGraph::TravelTimeGraph,
#     timeSpaceGraph::TimeSpaceGraph,
#     timeSpaceNode::Int,
#     bundle::Bundle,
# )
#     travelTimeNodes = Vector{Int}(undef, length(bundle.orders))
#     timeSpaceStep = timeSpaceGraph.timeSteps[timeSpaceNode]
#     # For each order of the bundle, computing the steps to delivery to know which travel time node should be used for the order
#     for (idx, order) in enumerate(bundle.orders)
#         stepToDel = order.deliveryDate - timeSpaceStep
#         # If the step to delivery is negative, adding the time horizon to it
#         stepToDel < 0 && (stepToDel += timeSpaceGraph.timeHorizon)
#         # If the step to delivery is greater than the max delivery time of the bundle, return -1
#         stepToDel > order.deliveryDate && (travelTimeNodes[idx] = -1; continue)
#         # Using time space link dict to return the right node idx
#         travelTimeNodes[idx] = travelTimeGraph.timeSpaceLink[hash(
#             stepToDel, timeSpaceGraph.networkNodes[timeSpaceNode].hash
#         )]
#     end
#     return travelTimeNodes
# end

# function travel_time_projector(
#     travelTimeGraph::TravelTimeGraph,
#     timeSpaceGraph::TimeSpaceGraph,
#     timeSpaceSource::Int,
#     timeSpaceDest::Int,
#     bundle::Bundle,
# )
#     return (
#         travel_time_projector(travelTimeGraph, timeSpaceGraph, timeSpaceSource, bundle),
#         travel_time_projector(travelTimeGraph, timeSpaceGraph, timeSpaceDest, bundle),
#     )
# end

function get_node_step_to_delivery(
    timeSpaceGraph::TimeSpaceGraph, timeSpaceNode::Int, order::Order
)
    # Computing the steps to delivery to know which travel time node should be used for the order
    stepToDel = order.deliveryDate - timeSpaceGraph.timeSteps[timeSpaceNode]
    # If the step to delivery is negative, adding the time horizon to it
    stepToDel < 0 && (stepToDel += timeSpaceGraph.timeHorizon)
    return stepToDel
end

# Project a node of the time space graph on the travel time graph for a specific order
# return -1 if the node time step is after the order delivery date or if the step to delivery is greater than the maximum delivery time 
function travel_time_projector(
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    timeSpaceNode::Int,
    order::Order,
)
    # If the time step is after the order delivery date, return -1
    timeSpaceGraph.timeSteps[timeSpaceNode] > order.deliveryDate && return -1
    # If the step to delivery is greater than the max delivery time, return -1
    stepToDel = get_node_step_to_delivery(timeSpaceGraph, timeSpaceNode, order)
    stepToDel > order.bundle.maxDeliveryTime && return -1
    # Using time space link dict to return the right node idx
    return travelTimeGraph.hashToIdx[hash(
        stepToDel, timeSpaceGraph.networkNodes[timeSpaceNode].hash
    )]
end

function travel_time_projector(
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    timeSpaceSource::Int,
    timeSpaceDest::Int,
    order::Order,
)
    return (
        travel_time_projector(travelTimeGraph, timeSpaceGraph, timeSpaceSource, order),
        travel_time_projector(travelTimeGraph, timeSpaceGraph, timeSpaceDest, order),
    )
end
