# Utils function for local search neighborhoods

function is_bin_candidate(bins::Vector{Bin}, arcData::NetworkArc; skipLinear::Bool)
    # If there is no bins, one bin or the arc is linear, skipping arc
    length(bins) <= 1 && return false
    skipLinear && arcData.isLinear && return false
    # If there is no gap with the lower bound, skipping arc
    arcVolume = sum(arcData.capacity - bin.capacity for bin in bins)
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
function save_previous_bins(
    solution::Solution,
    timeSpaceGraph::TimeSpaceGraph,
    workingArcs::SparseMatrixCSC{Bool,Int};
    current_cost::Bool,
)
    I, J, _ = findnz(workingArcs)
    oldBins = Vector{Vector{Bin}}(undef, length(workingArcs))
    # Efficient iteration over sparse matrices
    rows = rowvals(workingArcs)
    for timedDst in 1:size(workingArcs, 2)
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
    eachindex()
    for timedDst in 1:size(previousBins, 2)
        for srcIdx in nzrange(previousBins, timedDst)
            timedSrc = rows[srcIdx]
            # Reverting to previous bins
            solution.bins[timedSrc, timedDst] = previousBins[timedSrc, timedDst]
        end
    end
end

function save_and_remove_bundle!(
    solution::Solution,
    instance::Instance,
    bundles::Vector{Bundle},
    paths::Vector{Vector{Int}};
    current_cost::Bool,
    sorted::Bool,
)
    # Getting all timed arcs concerned
    workingArcs = get_bins_updated(TSGraph, TTGraph, bundles, paths)
    # Saving previous solution state 
    previousBins = save_previous_bins(
        solution, TSGraph, workingArcs; current_cost=current_cost
    )
    costRemoved = update_solution!(
        solution, instance, bundles, paths; remove=true, sorted=sorted
    )
    return previousBins, costRemoved
end

function best_reinsertion(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
    sorted::Bool,
    current_cost::Bool,
)
    # Computing shortest path
    greedyPath, greedyCost = greedy_insertion(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        src,
        dst;
        sorted=sorted,
        current_cost=current_cost,
    )
    lbPath, lbCost = lower_bound_insertion(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        src,
        dst;
        use_bins=true,
        current_cost=current_cost,
        giant=true,
    )
    # Computing real cost of lbPath
    update_cost_matrix!(
        solution,
        TTGraph,
        TSGraph,
        bundle;
        sorted=sorted,
        use_bins=true,
        current_cost=current_cost,
    )
    lbCost = get_path_cost(lbPath, TTGraph.costMatrix)
    # Selecting the best one
    if greedyCost < lbCost
        return greedyPath, greedyCost
    else
        return lbPath, lbCost
    end
end

function select_two_nodes(travelTimeGraph::TravelTimeGraph)
    node1 = rand(keys(travelTimeGraph.commonNodes))
    node2 = rand(keys(travelTimeGraph.commonNodes))
    while node1 == node2
        node2 = rand(keys(travelTimeGraph.commonNodes))
    end
    return node1, node2
end

function are_nodes_candidate(TTGraph::TravelTimeGraph, src::Int, dst::Int)
    src == dst && return false
    is_port(TTGraph, src) && is_port(TTGraph, dst) && return false
    return true
end

# Return a vector of bundles to update 
# If node 1 and node 2 are given : bundles that flow from 1 to 2
# If only node 1 : bundle that have node 1 for destination
function get_bundles_to_update(solution::Solution, node1::Int, node2::Int=-1)
    node2 == -1 && return solution.bundlesOnNodes[node1]
    return intersect(solution.bundlesOnNodes[node1], solution.bundlesOnNodes[node2])
end

function get_path_part(path::Vector{Int}, node1::Int, node2::Int)
    srcIdx = findfirst(node -> node == src, oldPath)
    dstIdx = findlast(node -> node == dst, oldPath)
    return path[srcIdx:dstIdx]
end

function get_paths_to_update(
    solution::Solution, bundles::Vector{Bundle}, node1::Int, node2::Int
)
    paths = Vector{Vector{Int}}(undef, length(bundles))
    for (idx, bundle) in enumerate(bundles)
        paths[idx] = get_path_part(solution.bundlePaths[bundle.idx], node1, node2)
    end
    return paths
end
