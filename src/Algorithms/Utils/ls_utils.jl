# Utils function for local search neighborhoods

function is_bin_candidate(bins::Vector{Bin}, arcData::NetworkArc; skipLinear::Bool)
    # If there is no bins, one bin or the arc is linear, skipping arc
    length(bins) <= 1 && return false
    skipLinear && arcData.isLinear && return false
    # If there is no gap with the lower bound, skipping arc
    arcVolume = sum(bin.load for bin in bins)
    ceil(arcVolume / arcData.capacity) == length(arcBins) && return false
    return true
end

function compute_new_bins(
    arcData::NetworkArc, allCommodities::Vector{Commodity}; sorted::Bool
)
    # TODO : parrallelize the recomputations with the different heuristics
    newBins = first_fit_decreasing(Bin[], arcData.capacity, allCommodities; sorted=sorted)
    bfdBins = best_fit_decreasing(Bin[], arcData.capacity, allCommodities; sorted=sorted)
    length(newBins) > length(bfdBins) && (newBins = bfdBins)
    return newBins
end

# Store previous bins before removing commodities from them
function save_previous_bins(solution::Solution, workingArcs::SparseMatrixCSC{Bool,Int};)
    I, J, _ = findnz(workingArcs)
    oldBins = Vector{Vector{Bin}}(undef, length(workingArcs))
    # Efficient iteration over sparse matrices
    rows = rowvals(workingArcs)
    for timedDst in 1:Base.size(workingArcs, 2)
        for srcIdx in nzrange(workingArcs, timedDst)
            timedSrc = rows[srcIdx]
            # Storing old bins
            oldBins[srcIdx] = deepcopy(solution.bins[timedSrc, timedDst])
        end
    end
    return sparse(I, J, oldBins)
end

# Revert the bin loading the the vector of bins given
function revert_bins!(solution::Solution, previousBins::SparseMatrixCSC{Vector{Bin},Int})
    # Efficient iteration over sparse matrices
    rows = rowvals(previousBins)
    for timedDst in 1:Base.size(previousBins, 2)
        for srcIdx in nzrange(previousBins, timedDst)
            timedSrc = rows[srcIdx]
            # Reverting to previous bins
            solution.bins[timedSrc, timedDst] = previousBins[timedSrc, timedDst]
        end
    end
end

# Saving and removing bundles
function save_and_remove_bundle!(
    solution::Solution,
    instance::Instance,
    bundles::Vector{Bundle},
    paths::Vector{Vector{Int}};
    current_cost::Bool=false,
)
    # Getting all timed arcs concerned
    workingArcs = get_bins_updated(TSGraph, TTGraph, bundles, paths)
    previousCost = 0.0
    if current_cost
        # compute cost with adapted function
    end
    # Saving previous solution state 
    previousBins = save_previous_bins(solution, workingArcs)
    costRemoved = update_solution!(solution, instance, bundles, paths; remove=true)
    if current_cost
        # compute cost with adapted function
        # difference is cost removed
    end
    return previousBins, costRemoved
end

# If I evaluate a path on the greedy cost matrix, either I have the same path 
# as the greedy one and the cost is the same, or I have a different path with 
# a worst cost because the greedy one is optimal for the greedy cost matrix
# It would make sense if several bundles were to be inserted

# function best_reinsertion(
#     solution::Solution,
#     TTGraph::TravelTimeGraph,
#     TSGraph::TimeSpaceGraph,
#     bundle::Bundle,
#     src::Int,
#     dst::Int;
#     sorted::Bool,
#     current_cost::Bool,
# )
#     # Computing shortest path
#     greedyPath, greedyCost = greedy_insertion(
#         solution,
#         TTGraph,
#         TSGraph,
#         bundle,
#         src,
#         dst;
#         sorted=sorted,
#         current_cost=current_cost,
#     )
#     lbPath, lbCost = lower_bound_insertion(
#         solution,
#         TTGraph,
#         TSGraph,
#         bundle,
#         src,
#         dst;
#         use_bins=true,
#         current_cost=current_cost,
#         giant=true,
#     )
#     # Computing real cost of lbPath
#     update_cost_matrix!(
#         solution,
#         TTGraph,
#         TSGraph,
#         bundle;
#         sorted=sorted,
#         use_bins=true,
#         current_cost=current_cost,
#     )
#     lbCost = path_cost(lbPath, TTGraph.costMatrix)
#     # Selecting the best one
#     if greedyCost < lbCost
#         return greedyPath, greedyCost
#     else
#         return lbPath, lbCost
#     end
# end

# Checking if two nodes are candidates for two node incremental
function are_nodes_candidate(TTGraph::TravelTimeGraph, src::Int, dst::Int)
    src == dst && return false
    is_port(TTGraph, src) && is_port(TTGraph, dst) && return false
    return true
end

# Selecting two nodes for two node incremental
function select_two_nodes(TTGraph::TravelTimeGraph)
    node1, node2 = rand(TTGraph.commonNodes, 2)
    while !are_nodes_candidate(TTGraph, node1, node2)
        node1, node2 = rand(TTGraph.commonNodes, 2)
    end
    return node1, node2
end

# Return a vector of bundles to update 
# If node 1 and node 2 are given : bundles that flow from 1 to 2
# If only node 1 : bundle that have node 1 for destination
function get_bundles_to_update(solution::Solution, node1::Int, node2::Int=-1)
    node2 == -1 && return solution.bundlesOnNodes[node1]
    return intersect(solution.bundlesOnNodes[node1], solution.bundlesOnNodes[node2])
end

function get_paths_to_update(
    solution::Solution, bundles::Vector{Bundle}, node1::Int, node2::Int
)
    paths = Vector{Vector{Int}}(undef, length(bundles))
    for (idx, bundle) in enumerate(bundles)
        oldPath = solution.bundlePaths[bundle.idx]
        srcIdx = findfirst(node -> node == node1, oldPath)
        dstIdx = findlast(node -> node == node2, oldPath)
        paths[idx] = path[srcIdx:dstIdx]
    end
    return paths
end
