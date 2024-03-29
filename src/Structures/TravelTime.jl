# Graph structure used to compute bundle paths 

# TODO : change name to delivery graph to avoid confusion with arc travel times ?

# TODO : add field description
# Travel Time Graph
struct TravelTimeGraph
    graph :: DiGraph
    networkNodes :: Vector{NetworkNode}
    networkArcs :: SparseMatrixCSC{NetworkArc, Int}
    stepToDel :: Vector{Int}
end

struct TravelTimeUtils
    costMatrix :: SparseMatrixCSC{Float64, Int}
    commonNodes :: Vector{Int}
    bundleStartNodes :: Vector{Int}
    bundleEndNodes :: Vector{Int}
    bundlesOnNode :: Dict{Int, Vector{Bundle}} 
end

# For networkNodes and networkArcs creation : pre-allocating memory (or pushing) stores only a shallow copy of objects 

# Methods

# TODO : put all major block in functions
function build_travel_time_and_utils(network::NetworkGraph, bundles::Vector{Bundle})
    # Computing for each node which bundles starts and which bundles end at this node 
    bundlesOnSupplier = Dict{UInt, Vector{Bundle}}()
    bundlesOnCustomer = Dict{UInt, Vector{Bundle}}()
    bundlesMaxDelTime = Dict{UInt, Int}()
    bundleIndexes = Dict{UInt, Int}()
    for (idx, bundle) in enumerate(bundles)
        suppHash = hash(bundle.supplier)
        supplierBundles = get!(bundlesOnSupplier, suppHash, Bundle[])
        push!(supplierBundles, bundle)
        custHash = hash(bundle.customer)
        customerBundles = get!(bundlesOnCustomer, custHash, Bundle[])
        push!(customerBundles, bundle)
        bundleMaxTime[hash(bundle)] = 1 + network[suppHash, custHash].travelTime
        bundlesIndexes[hash(bundle)] = idx
    end
    overallMaxDelTime = maximum(values(bundleMaxTime))
    # Initializing structures
    travelTimeGraph = TravelTimeGraph(DiGraph(), NetworkNode[], sparse(zeros(Int, 0, 0)), Int[])
    travelTimeUtils = TravelTimeUtils(sparse(zeros(Float64, 0, 0)), Int[], zeros(Int, length(bundles)), zeros(Int, length(bundles)), Dict{Int, Vector{Bundle}}())
    # Adding all nodes from the network graph
    for nodeHash in labels(network)
        nodeData = network[nodeHash]
        # Computing the number of times we have to add a timed copy of the node 
        # plant = 0, suppliers = max of bundle del time, platforms = overall max del time (done with init cond in max)
        nodeExtraCopies = nodeData.type == :plant ? 0 : maximum(bundleMaxTime[hash(bundle)] for bundle in bundlesOnSupplier[nodeHash], init=overallMaxDelTime) - 1
        for stepToDel in 0:nodeExtraCopies
            # Adding timed copy to the graph
            add_vertex!(travelTimeGraph.graph)
            nodeIdx = nv(travelTimeGraph.graph)
            push!(travelTimeGraph.networkNodes, nodeData)
            push!(travelTimeGraph.stepToDel, stepToDel)
            # if supplier, checking if bundles with maxDelTime corresponds
            if nodeData.type == :supplier
                startOnNode = filter(bundle -> bundleMaxTime[hash(bundle)] == stepToDel, bundlesOnSupplier[nodeHash])
                for bundle in startOnNode
                    travelTimeUtils.bundleStartNodes[bundleIndexes[hash(bundle)]] = nodeIdx
                end
                continue
            end
            # if plant, adding corresponding bundles
            if nodeData.type == :plant
                for bundle in bundlesOnSupplier[nodeHash]
                    travelTimeUtils.bundleEndNodes[bundleIndexes[hash(bundle)]] = nodeIdx
                end
                continue
            end
            # else its a platform, adding to common nodes
            push!(travelTimeUtils.commonNodes, nodeIdx)
        end
    end
    # Initializing vectors for sparse matrices
    I, J = Int[], Int[]
    arcs, costs = NetworkArc[], Float64[]
    nodesHash = hash.(travelTimeGraph.networkNodes)
    # Adding all arcs form the network graph
    for (sourceHash, destHash) in edge_labels(network)
        arcData = network[sourceHash, destHash]
        # I get all source node copies and dest node copies (via hash)
        sourceNodeIdxs = findall(nodeHash -> nodeHash == sourceHash, nodesHash)
        destNodeIdxs = findall(nodeHash -> nodeHash == destHash, nodesHash)
        # I add an arc when source step to del - arc travel time = dest step to del
        for sourceNodeIdx in sourceNodeIdxs, destNodeIdx in destNodeIdxs
            if travelTimeGraph.stepToDel[sourceNodeIdx] - arcData.travelTime == travelTimeGraph.stepToDel[destNodeIdx]
                push!(I, sourceNodeIdx)
                push!(J, destNodeIdx)
                push!(arcs, arcData)
                push!(costs, EPS)
            end
        end
        # Also add shortcut
        for sourceNodeIdx1 in sourceNodeIdxs, sourceNodeIdx2 in sourceNodeIdxs
            if travelTimeGraph.stepToDel[sourceNodeIdx1] - 1 == travelTimeGraph.stepToDel[sourceNodeIdx2]
                push!(I, sourceNodeIdx1)
                push!(J, sourceNodeIdx2)
                push!(arcs, NetworkArc(:shortcut, EPS, 1, false, 0., false, 0., 0))
                push!(costs, EPS)
            end
        end
    end
    # Building sparse matrix
    arcMatrix = sparse(I, J, arcs)
    costMatrix = sparse(I, J, costs)
    # Creating final structures
    finalTravelTime = TravelTimeGraph(travelTimeGraph.graph, travelTimeGraph.networkNodes, arcMatrix, travelTimeGraph.stepToDel)
    finalTravelTimeUtils = TravelTimeUtils(costMatrix, travelTimeUtils.commonNodes, travelTimeUtils.bundleStartNodes, travelTimeUtils.bundleEndNodes, travelTimeUtils.bundleOnNodes)
    return finalTravelTime, finalTravelTimeUtils
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
    # Also return the start / end node for each bundle
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

# Compute for each bundle the maximum delivery time allowed (for now : direct time + 1 week)
function get_max_delivery_time(network::NetworkGraph)
    
end