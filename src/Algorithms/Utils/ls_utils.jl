# Utils function for local search neighborhoods

function is_bin_candidate(bins::Vector{Bin}, arcData::NetworkArc; skipLinear::Bool)
    # If there is no bins, one bin or the arc is linear, skipping arc
    length(bins) <= 1 && return false
    skipLinear && arcData.isLinear && return false
    # If there is no gap with the lower bound, skipping arc
    arcVolume = sum(bin.load for bin in bins)
    ceil(arcVolume / arcData.capacity) == length(bins) && return false
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
    oldBins = Vector{Vector{Bin}}(undef, length(I))
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
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
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

# Compute paths for both insertion type 
function both_insertion(
    solution::Solution,
    instance::Instance,
    bundle::Bundle,
    src::Int,
    dst::Int;
    sorted::Bool=false,
    current_cost::Bool=false,
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    greedyPath, pathCost = greedy_insertion(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        src,
        dst;
        sorted=sorted,
        current_cost=current_cost,
    )
    lowerBoundPath, pathCost = lower_bound_insertion(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        src,
        dst;
        use_bins=true,
        giant=true,
        current_cost=current_cost,
    )
    return greedyPath, lowerBoundPath
end

# Change solution paths and bins into other solution paths and bins
# Must be the last ones added
function change_solution_to_other!(
    sol::Solution,
    other::Solution,
    instance::Instance,
    bundles::Vector{Bundle};
    sorted::Bool=false,
)
    # Removing added path by greedy update 
    update_solution!(
        sol, instance, bundles, sol.bundlePaths[idx(bundles)]; remove=true, skipRefill=true
    )
    # We can skip refill and just clean the bins as the commodities were the last added
    clean_empty_bins!(sol, instance)
    # Adding lower bound ones
    update_solution!(sol, instance, bundles, other.bundlePaths[idx(bundles)]; sorted=sorted)
    return nothing
end

# Checking if two nodes are candidates for two node incremental
function are_nodes_candidate(TTGraph::TravelTimeGraph, src::Int, dst::Int)
    src == dst && return false
    is_port(TTGraph, src) && is_port(TTGraph, dst) && return false
    TTGraph.stepToDel[src] < TTGraph.stepToDel[dst] && return false
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

function is_node1_before_node2(path::Vector{Int}, node1::Int, node2::Int)
    # look for the first node encountered
    idx = findfirst(node -> (node == node1) || (node == node2), path)
    return path[idx] == node1
end

# Return a vector of bundles to update 
# If node 1 and node 2 are given : bundles that flow from 1 to 2
# If only node 1 : bundle that have node 1 for destination
function get_bundles_to_update(solution::Solution, node1::Int, node2::Int=-1)
    node2 == -1 && return solution.bundlesOnNode[node1]
    twoNodeBundles = intersect(solution.bundlesOnNode[node1], solution.bundlesOnNode[node2])
    return filter(
        b -> is_node1_before_node2(solution.bundlePaths[b.idx], node1, node2),
        twoNodeBundles,
    )
end

function get_paths_to_update(
    solution::Solution, bundles::Vector{Bundle}, node1::Int, node2::Int
)
    paths = Vector{Vector{Int}}(undef, length(bundles))
    for (idx, bundle) in enumerate(bundles)
        oldPath = solution.bundlePaths[bundle.idx]
        srcIdx = findfirst(node -> node == node1, oldPath)
        dstIdx = findlast(node -> node == node2, oldPath)
        paths[idx] = oldPath[srcIdx:dstIdx]
    end
    return paths
end

# TODO : this info can be stored in the solution to go faster, just a vector of Float64 to be updated in update_solution!
function bundle_path_linear_cost(
    bundle::Bundle, path::Vector{Int}, TTGraph::TravelTimeGraph
)
    cost = 0.0
    for (i, j) in partition(path, 2, 1), order in bundle.orders
        cost += volume_stock_cost(TTGraph, i, j, order)
        arcData = TTGraph.networkArcs[i, j]
        !arcData.isLinear && continue
        # for linear arcs, adding transport cost 
        cost += get_transport_units(order, arcData) * arcData.unitCost
    end
    return cost
end

# compute the maximum removal cost of a bundle
function bundle_max_removal_cost(
    bundle::Bundle, path::Vector{Int}, TTGraph::TravelTimeGraph
)
    cost = 0.0
    for (i, j) in partition(path, 2, 1), order in bundle.orders
        cost += volume_stock_cost(TTGraph, i, j, order)
        arcData = TTGraph.networkArcs[i, j]
        cost += get_transport_units(order, arcData) * arcData.unitCost
    end
    return cost
end

# TODO : create a revert solution function to make it clearer in the code
