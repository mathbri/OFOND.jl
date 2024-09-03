# Local search heuristic and building blocks

# There will be a need to adapt to the new route design formulation
# For the bundles that do not need / already use an oversea arc :
#    - just changing the bundle def / creation will solve things
# For the bundle that use oversea arc :
#    - reintroduce once with the old formulation (one route / 3 months)
#    - then try to optimize path to and from ports with the new formulation
# This double calculation can be done for every bundle if we want to add / remove oversea arcs from routes
# How to handle the two node incremental ? 
#    - a simple solution is to exclude bundles use oversea arcs
# Bin packing neighborhood does not change

# For the minimal flow on maritime arcs, one solution is to check at removal time if the quantities left satisfy the minimal flow, if not just recomuting path to and from oversea arc 
# At insertion time, if the added flow don't make enough for the constraint, arc is forbidden (INF) cost
# Another option for insertion is to make a first round of insertion without constraint and if there is arcs that does not satisfy, 
#    - take all bundles of it, forbid arc for every one and recompute insertion and repaeat until constraint are good

# Other question : 
# Instead of computing greedy and lower boud paths, would it be better to divide it into two different operators ?
# Like reintroduce all bundles with greedy path and then reintroduce all bundles with lower bound paths ?

# Improving all bin packings if possible
# The idea is to put skip linear to false just before returning the solution to get a more compact solution but it does not affect the cost
function bin_packing_improvement!(
    solution::Solution, instance::Instance; sorted::Bool=false, skipLinear::Bool=true
)
    costImprov, computedNoImprov, computable = 0.0, 0, 0
    for arc in edges(instance.timeSpaceGraph.graph)
        arcBins = solution.bins[src(arc), dst(arc)]
        arcData = instance.timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        length(arcBins) > 1 && (computable += 1)
        # If no improvement possible
        is_bin_candidate(arcBins, arcData; skipLinear=skipLinear) || continue
        # Gathering all commodities
        # TODO : again the get all commodities that is impeding performance, check usage of this neighborhood to know if you need to pass ALL_COMMODITIES as argument
        allCommodities = get_all_commodities(arcBins)
        # Computing new bins
        newBins = compute_new_bins(arcData, allCommodities; sorted=sorted)
        # If the number of bins did not change, skipping next
        if length(newBins) >= length(arcBins)
            computedNoImprov += 1
            # TODO : test this again with combinatorial instance
            # optBins = milp_packing(Bin[], arcData.capacity, allCommodities)
            # if length(optBins) < length(arcBins)
            #     optImprov = -arcData.unitCost * (length(arcBins) - optBins)
            #     @warn "Optimal packing could have improved of $optImprov ($(length(arcBins) - optBins) bins)"
            # end
            continue
        end
        # Updating bins
        solution.bins[src(arc), dst(arc)] = newBins
        # Computing cost improvement (unless linear arc)
        arcData.isLinear && continue
        costImprov -= arcData.unitCost * (length(arcBins) - length(newBins))
    end
    println("All packings computable : $computable")
    println("Computed packings with no improvement : $computedNoImprov")
    return costImprov
end

# All arcs are independant when computing bin-packing so can be parrallelized
function parrallel_bin_packing_improvement!(
    solution::Solution, instance::Instance; sorted::Bool=false, skipLinear::Bool=true
)
    # TODO : parrallelize here with native @threads
    # TODO : check memory sharing between threads if the get all commodity workaround is in place
end

# TODO : major profiling problems in bundle reintroduction comes from the deepcopy done in save and remove
# Maybe doing the same thing as the capacities in tentative first fit 
# Meaning dedicated a pre-allocated object used to save previous state of the solution 

# TODO : the goal with the analysis would te to know if the first try with all bundles and the other tries with a subset of bundles are better

# TODO : would sorting bundles by estimated removal cost a good idea ?

# TODO : if I store the order in which the bundles were inserted on the arcs, there is no need to gather all commodities in refilling : another "global" matrix to use for all computations ? or update solutions with remove returns the previous order insertion matrix of the solution
# The problem being that cost increase in removal than insertion goes up to 200 000 for world instance
# But if the bin packing improvement neighborhood change the bin filling, this order no longer makes sense
# So need to remove it if the bin pack found better solution

function revert_solution!(
    solution::Solution,
    instance::Instance,
    bundles::Vector{Bundle},
    oldPaths::Vector{Vector{Int}},
    oldBins::SparseMatrixCSC{Vector{Bin},Int},
    newPaths::Vector{Vector{Int}}=[Int[]],
)
    if length(newPaths[1]) > 0
        update_solution!(solution, instance, bundles, newPaths; remove=true)
    end
    update_solution!(solution, instance, bundles, oldPaths; skipRefill=true)
    return revert_bins!(solution, oldBins)
    # More efficient solution but some cost increase
    # update_solution!(solution, instance, twoNodeBundles, newPaths; remove=true)
    # updateCost = update_solution!(
    #     solution, instance, twoNodeBundles, oldPaths; sorted=sorted
    # )
    # if updateCost + costRemoved > 1e3
    #     binsUpdated = get_bins_updated(TSGraph, TTGraph, twoNodeBundles, oldPaths)
    #     refillCostChange = refill_bins!(solution, TSGraph, binsUpdated)
    #     if updateCost + costRemoved + refillCostChange > 1e3
    #         println()
    #         @warn "Two Node Incremental : Removal than insertion lead to cost increase of $(round(updateCost + costRemoved + refillCostChange)) (removed $(round(costRemoved)), added $(round(updateCost))) and refill made $(round(refillCostChange))"
    #     end
    #     return updateCost + costRemoved + refillCostChange
    # end
end

# Removing and inserting back the bundle in the solution.
# If the operation did not lead to a cost improvement, reverting back to the former state of the solution.
function bundle_reintroduction!(
    solution::Solution,
    instance::Instance,
    bundle::Bundle,
    CAPACITIES::Vector{Int};
    sorted::Bool=false,
    current_cost::Bool=false,
    costThreshold::Float64=EPS,
)::Float64
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    oldPath = solution.bundlePaths[bundle.idx]
    # The filtering could also occur in terms of cost removed : it must be above a certain threshold
    bundle_estimated_removal_cost(bundle, oldPath, instance, solution) <= costThreshold &&
        return 0.0

    # Saving previous bins and removing bundle
    oldBins = save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, [bundle], [oldPath])
    )
    costRemoved = update_solution!(solution, instance, bundle, oldPath; remove=true)

    # Inserting it back
    suppNode = TTGraph.bundleSrc[bundle.idx]
    custNode = TTGraph.bundleDst[bundle.idx]
    newPath, pathCost = greedy_insertion(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        suppNode,
        custNode,
        CAPACITIES;
        sorted=sorted,
        current_cost=current_cost,
    )

    # Updating path if it improves the cost (accounting for EPS cost on arcs)
    if pathCost + costRemoved < -1e-3
        # Adding to solution
        update_solution!(solution, instance, bundle, newPath; sorted=sorted)
        return pathCost + costRemoved
    else
        revert_solution!(solution, instance, [bundle], [oldPath], oldBins)
        return 0.0
    end
end

# Remove and insert back all bundles flowing from src to dst 
function two_node_incremental!(
    solution::Solution,
    instance::Instance,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int};
    sorted::Bool=false,
    current_cost::Bool=false,
    costThreshold::Float64=EPS,
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    twoNodeBundleIdxs = get_bundles_to_update(instance, solution, src, dst)
    twoNodeBundles = instance.bundles[twoNodeBundleIdxs]
    # If there is no bundles concerned, returning
    length(twoNodeBundles) == 0 && return 0.0
    oldPaths = get_paths_to_update(solution, twoNodeBundles, src, dst)

    # The filtering could also occur in terms of cost removed : it must be above a certain threshold
    sum(
        bundle_estimated_removal_cost(bundle, path, instance, solution) for
        (bundle, path) in zip(twoNodeBundles, oldPaths)
    ) <= costThreshold && return 0.0

    # Saving previous bins and removing bundle 
    oldBins = save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, twoNodeBundles, oldPaths)
    )
    costRemoved = update_solution!(
        solution, instance, twoNodeBundles, oldPaths; remove=true
    )

    # If the cost removed only amouts to the linear part of the cost, improvements are too small compared to the computational cost
    pathsLinearCost = sum(
        bundle_path_linear_cost(bundle, path, TTGraph) for
        (bundle, path) in zip(twoNodeBundles, oldPaths)
    )
    if costRemoved + pathsLinearCost >= -EPS
        revert_solution!(solution, instance, twoNodeBundles, oldPaths, oldBins)
        return 0.0
    end

    # TODO : try adding all on the same path 
    # Inserting it back
    addedCost = 0.0
    # sortedBundleIdxs = sortperm(twoNodeBundles; by=bun -> bun.maxPackSize, rev=true)
    sortedBundleIdxs = randperm(length(twoNodeBundles))
    newPaths = [Int[] for _ in 1:length(twoNodeBundles)]
    for bundleIdx in sortedBundleIdxs
        bundle = twoNodeBundles[bundleIdx]
        newPath, pathCost = greedy_insertion(
            solution,
            TTGraph,
            TSGraph,
            bundle,
            src,
            dst,
            CAPACITIES;
            sorted=sorted,
            current_cost=current_cost,
        )
        # Adding to solutions
        addedCost += update_solution!(solution, instance, bundle, newPath; sorted=sorted)
        newPaths[bundleIdx] = newPath
    end

    # Solution already updated so if it didn't improve, reverting to old state
    if addedCost + costRemoved > -1e-3
        revert_solution!(solution, instance, twoNodeBundles, oldPaths, oldBins, newPaths)
        return 0.0
    else
        return addedCost + costRemoved
    end
end

# TODO : Mix this two by doing the together first and then the incremental in a reintridcution fashion to question the common path
# By changing middle parts of paths, some can become non-admissible
# Good idea but can't make it work for now

# TODO : to be optimized to the fullest because works better than classical local search 

function two_node_common_incremental!(
    solution::Solution,
    instance::Instance,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int};
    costThreshold::Float64=EPS,
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    twoNodeBundleIdxs = get_bundles_to_update(instance, solution, src, dst)
    twoNodeBundles = instance.bundles[twoNodeBundleIdxs]
    # If there is no bundles concerned, returning
    length(twoNodeBundles) == 0 && return 0.0
    oldPaths = get_paths_to_update(solution, twoNodeBundles, src, dst)

    # Saving previous bins and removing bundle 
    prevSol = solution_deepcopy(solution, instance)
    costRemoved = update_solution!(
        solution, instance, twoNodeBundles, oldPaths; remove=true
    )

    # Creating a unique bundle for all the bundles concerned
    # Putting one order for each delivery date to fuse them together
    newOrders = [Order(UInt(0), i) for i in 1:(instance.timeHorizon)]
    for bundle in twoNodeBundles
        # Fusing all orders
        for order in bundle.orders
            append!(newOrders[order.deliveryDate].content, order.content)
        end
    end
    filter!(o -> length(o.content) > 0, newOrders)
    for order in newOrders
        sort!(order.content)
    end
    newOrders = [
        add_properties(order, tentative_first_fit, CAPACITIES) for order in newOrders
    ]
    bunIdx = twoNodeBundleIdxs[1]
    commonBundle = Bundle(
        twoNodeBundles[1].supplier,
        twoNodeBundles[1].customer,
        newOrders,
        bunIdx,
        UInt(0),
        0,
        0,
    )

    # Inserting it back
    newPath, pathCost = greedy_insertion(
        solution,
        TTGraph,
        TSGraph,
        commonBundle,
        src,
        dst,
        CAPACITIES;
        sorted=true,
        findSources=false,
    )

    # Updating solution for the next step
    newPaths = [newPath for _ in 1:length(twoNodeBundles)]
    updateCost = update_solution!(solution, instance, twoNodeBundles, newPaths; sorted=true)
    improvement = updateCost + costRemoved

    # Inserting back concerned bundles
    for (i, bIdx) in enumerate(twoNodeBundleIdxs)
        bundle = instance.bundles[bIdx]
        improvement += bundle_reintroduction!(
            solution, instance, bundle, CAPACITIES; sorted=true, costThreshold=1.0
        )
        i % 10 == 0 && print(".")
    end

    # If no improvement at the end, reverting solution to its first state
    if improvement > 1e2
        newPaths = deepcopy(solution.bundlePaths)
        revert_solution!(
            solution,
            instance,
            instance.bundles,
            prevSol.bundlePaths,
            prevSol.bins,
            newPaths,
        )
        print("x")
        return 0.0
    elseif !is_feasible(instance, solution)
        newPaths = deepcopy(solution.bundlePaths)
        revert_solution!(
            solution,
            instance,
            instance.bundles,
            prevSol.bundlePaths,
            prevSol.bins,
            newPaths,
        )
        print("X")
        return 0.0
    else
        print("o")
        return improvement
    end
end

function two_node_common!(
    solution::Solution,
    instance::Instance,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int};
    costThreshold::Float64=EPS,
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    twoNodeBundleIdxs = get_bundles_to_update(instance, solution, src, dst)
    twoNodeBundles = instance.bundles[twoNodeBundleIdxs]
    # If there is no bundles concerned, returning
    length(twoNodeBundles) == 0 && return 0.0
    oldPaths = get_paths_to_update(solution, twoNodeBundles, src, dst)

    # Saving previous bins and removing bundle 
    oldBins = save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, twoNodeBundles, oldPaths)
    )
    costRemoved = update_solution!(
        solution, instance, twoNodeBundles, oldPaths; remove=true
    )

    # Creating a unique bundle for all the bundles concerned
    # Putting one order for each delivery date to fuse them together
    newOrders = [Order(UInt(0), i) for i in 1:(instance.timeHorizon)]
    for bundle in twoNodeBundles
        # Fusing all orders
        for order in bundle.orders
            append!(newOrders[order.deliveryDate].content, order.content)
        end
    end
    filter!(o -> length(o.content) > 0, newOrders)
    for order in newOrders
        sort!(order.content)
    end
    newOrders = [
        add_properties(order, tentative_first_fit, CAPACITIES) for order in newOrders
    ]
    bunIdx = twoNodeBundleIdxs[1]
    commonBundle = Bundle(
        twoNodeBundles[1].supplier,
        twoNodeBundles[1].customer,
        newOrders,
        bunIdx,
        UInt(0),
        0,
        0,
    )

    # Inserting it back
    newPath, pathCost = greedy_insertion(
        solution,
        TTGraph,
        TSGraph,
        commonBundle,
        src,
        dst,
        CAPACITIES;
        sorted=true,
        findSources=false,
    )

    # Updating solution for the next step
    newPaths = [newPath for _ in 1:length(twoNodeBundles)]
    updateCost = update_solution!(solution, instance, twoNodeBundles, newPaths; sorted=true)
    improvement = updateCost + costRemoved

    # If no improvement at the end, reverting solution to its first state
    if improvement > 1e2
        revert_solution!(solution, instance, twoNodeBundles, oldPaths, oldBins, newPaths)
        print("x")
        return 0.0
    elseif !is_feasible(instance, solution)
        revert_solution!(solution, instance, twoNodeBundles, oldPaths, oldBins, newPaths)
        print("X")
        return 0.0
    else
        print("o")
        return improvement
    end
end

function two_node_common_incremental_debug!(
    solution::Solution,
    instance::Instance,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int};
    costThreshold::Float64=EPS,
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    twoNodeBundleIdxs = get_bundles_to_update(instance, solution, src, dst)
    twoNodeBundles = instance.bundles[twoNodeBundleIdxs]
    # If there is no bundles concerned, returning
    length(twoNodeBundles) == 0 && return 0.0
    oldPaths = get_paths_to_update(solution, twoNodeBundles, src, dst)

    # The filtering could also occur in terms of cost removed : it must be above a certain threshold
    # sum(
    #     bundle_estimated_removal_cost(bundle, path, instance, solution) for
    #     (bundle, path) in zip(twoNodeBundles, oldPaths)
    # ) <= costThreshold && return 0.0

    # Checking bundles paths and bundles on nodes corresponds
    # for bundle in instance.bundles
    #     for node in solution.bundlePaths[bundle.idx][2:end]
    #         @assert bundle.idx in solution.bundlesOnNode[node]
    #     end
    # end
    # for node in keys(solution.bundlesOnNode)
    #     for bunIdx in solution.bundlesOnNode[node]
    #         @assert node in solution.bundlePaths[bunIdx][2:end]
    #     end
    # end
    @assert is_feasible(instance, solution)

    # Saving previous bins and removing bundle 
    prevSol = solution_deepcopy(solution, instance)
    # oldBins = save_previous_bins(
    #     solution, get_bins_updated(TSGraph, TTGraph, twoNodeBundles, oldPaths)
    # )
    costRemoved = update_solution!(
        solution, instance, twoNodeBundles, oldPaths; remove=true
    )

    # If the cost removed only amouts to the linear part of the cost, improvements are too small compared to the computational cost
    # pathsLinearCost = sum(
    #     bundle_path_linear_cost(bundle, path, TTGraph) for
    #     (bundle, path) in zip(twoNodeBundles, oldPaths)
    # )
    # if costRemoved + pathsLinearCost >= -EPS
    #     revert_solution!(solution, instance, twoNodeBundles, oldPaths, oldBins)

    #     # Checking bundles paths and bundles on nodes corresponds
    #     for bundle in instance.bundles
    #         for node in solution.bundlePaths[bundle.idx][2:end]
    #             @assert bundle.idx in solution.bundlesOnNode[node]
    #         end
    #     end
    #     for node in keys(solution.bundlesOnNode)
    #         for bunIdx in solution.bundlesOnNode[node]
    #             @assert node in solution.bundlePaths[bunIdx][2:end]
    #         end
    #     end
    #     @assert is_feasible(instance, solution)

    #     return 0.0
    # end
    # Creating a unique bundle for all the bundles concerned
    commonBundle = fuse_bundles(instance, twoNodeBundles)

    # Inserting it back
    newPath, pathCost = greedy_insertion(
        solution,
        TTGraph,
        TSGraph,
        commonBundle,
        src,
        dst,
        CAPACITIES;
        sorted=true,
        findSources=false,
    )

    # Updating solution for the next step
    newPaths = [newPath for _ in 1:length(twoNodeBundles)]
    updateCost = update_solution!(solution, instance, twoNodeBundles, newPaths; sorted=true)
    improvement = updateCost + costRemoved
    # If improvement, changing old paths
    # print(" common $(round(improvement, digits=1)) ")
    # if improvement < -1
    #     prevSol = solution_deepcopy(solution, instance)
    # end
    # @assert is_feasible(instance, solution)

    for (i, bIdx) in enumerate(twoNodeBundleIdxs)
        bundle = instance.bundles[bIdx]
        improvement += bundle_reintroduction!(
            solution, instance, bundle, CAPACITIES; sorted=true, costThreshold=1.0
        )
        print(".")
    end
    @assert is_feasible(instance, solution)

    # Checking bundles paths and bundles on nodes corresponds
    # for bundle in instance.bundles
    #     for node in solution.bundlePaths[bundle.idx][2:end]
    #         if !(bundle.idx in solution.bundlesOnNode[node])
    #             println("bundle $bundle")
    #             localIdx = findfirst(x -> x == bundle.idx, twoNodeBundleIdxs)
    #             println("old path $(oldPaths[localIdx])")
    #             println("new path $(commonPaths[localIdx])")
    #             println("node $node and bundles on node $(solution.bundlesOnNode[node])")
    #         end
    #         @assert bundle.idx in solution.bundlesOnNode[node]
    #     end
    # end
    # for node in keys(solution.bundlesOnNode)
    #     for bunIdx in solution.bundlesOnNode[node]
    #         if !(node in solution.bundlePaths[bunIdx][2:end])
    #             println("bundle $(instance.bundles[bunIdx])")
    #             localIdx = findfirst(x -> x == bunIdx, twoNodeBundleIdxs)
    #             println("old path $(oldPaths[localIdx])")
    #             println(
    #                 "new path $(commonPaths[localIdx]) (full path $(solution.bundlePaths[bunIdx]))",
    #             )
    #             println("node $node and bundles on node $(solution.bundlesOnNode[node])")
    #         end
    #         @assert node in solution.bundlePaths[bunIdx][2:end]
    #     end
    # end

    # Some new path parts can render the whole bundle path non-admissible
    # for (i, bundle) in enumerate(twoNodeBundles)
    #     updateCost, costRemoved = 0.0, 0.0
    #     # If the new path is admissible 
    #     if is_path_admissible(TTGraph, solution.bundlePaths[bundle.idx])
    #         # Inserting it back again to try to gain more
    #         oldPath = get_paths_to_update(solution, [bundle], src, dst)[1]
    #         fullOldPath = solution.bundlePaths[bundle.idx]
    #         # TODO : It seems like here all the commodities of the two node bundles were removed instead of just the one of the bundle
    #         costRemoved = update_solution!(solution, instance, bundle, oldPath; remove=true)
    #         # Inserting it back
    #         newPath, pathCost = greedy_insertion(
    #             solution, TTGraph, TSGraph, bundle, src, dst, CAPACITIES; sorted=true
    #         )
    #         updateCost = update_solution!(solution, instance, bundle, newPath; sorted=true)
    #         # TODO : need to revert if re-intro did not lead to an improvement
    #         if !is_feasible(instance, solution)
    #             # As a quick fix, we can revert the solution to the previous state
    #             println("Reverting solution because of infeasibility")
    #             @assert is_feasible(instance, prevSol)
    #             newPaths = deepcopy(solution.bundlePaths)
    #             revert_solution!(
    #                 solution,
    #                 instance,
    #                 instance.bundles,
    #                 prevSol.bundlePaths,
    #                 prevSol.bins,
    #                 newPaths,
    #             )
    #             println("Reverted solution")
    #             @assert is_feasible(instance, solution)
    #             break
    #             # println("two node bundle $twoNodeBundleIdxs")
    #             # println("bundle $bundle")
    #             # println("Bundle introduced orders")
    #             # for order in bundle.orders
    #             #     println(order)
    #             # end
    #             # println("Common bundle orders")
    #             # for order in commonBundle.orders
    #             #     println(order)
    #             # end
    #             # println("full old path $fullOldPath")
    #             # println("old path $oldPath and cost removed $costRemoved")
    #             # println("new path $(newPath) and cost added $pathCost ($updateCost)")
    #             # throw(ErrorException("Infeasible solution"))
    #         end
    #     end
    #     # Re introducing bundles with non-admissible paths
    #     if !is_path_admissible(TTGraph, solution.bundlePaths[bundle.idx])
    #         oldPath = solution.bundlePaths[bundle.idx]
    #         costRemoved = update_solution!(solution, instance, bundle, oldPath; remove=true)
    #         # Inserting it back
    #         bSrc = TTGraph.bundleSrc[bundle.idx]
    #         bDst = TTGraph.bundleDst[bundle.idx]
    #         newPath, pathCost = greedy_insertion(
    #             solution, TTGraph, TSGraph, bundle, bSrc, bDst, CAPACITIES; sorted=true
    #         )
    #         updateCost = update_solution!(solution, instance, bundle, newPath; sorted=true)
    #     end
    #     println(" re-intro $(round(updateCost + costRemoved, digits=1)) ")
    #     improvement += updateCost + costRemoved
    # end

    # Checking the improvement

    # Keeping only bundles where new path part is admissible
    # twoNodeBundles = twoNodeBundles[idxToKeep]
    # oldPaths = oldPaths[idxToKeep]
    # commonPaths = commonPaths[idxToKeep]

    # For each bundle, removing it and inserting it back between src and dst individually
    # bunIdxs = randperm(length(twoNodeBundles))
    # newPaths = [Vector{Int}() for _ in 1:length(twoNodeBundles)]
    # for bIdx in bunIdxs
    #     bundle = twoNodeBundles[bIdx]
    #     oldPath = oldPaths[bIdx]
    #     # Saving previous bins and removing bundle
    #     bunOldBins = save_previous_bins(
    #         solution, get_bins_updated(TSGraph, TTGraph, [bundle], [oldPath])
    #     )
    #     costRemoved = update_solution!(solution, instance, bundle, oldPath; remove=true)

    #     # Inserting it back
    #     newPath, pathCost = greedy_insertion(
    #         solution, TTGraph, TSGraph, bundle, src, dst, CAPACITIES; sorted=true
    #     )

    #     # Updating path if it improves the cost and the whole path remains admissible
    #     if pathCost + costRemoved < -1e-3 &&
    #         all(n -> !(n in solution.bundlePaths[bundle.idx]), newPath[2:(end - 1)])
    #         print(" single ")
    #         newPaths[bIdx] = newPath
    #         # Adding to solution
    #         update_solution!(solution, instance, bundle, newPath; sorted=true)
    #         # if is_path_admissible(TTGraph, solution.bundlePaths[bundle.idx])
    #         #     improvement += pathCost + costRemoved
    #         # else
    #         #     revert_solution!(
    #         #         solution, instance, [bundle], [oldPath], bunOldBins, [newPath]
    #         #     )
    #         #     newPaths[bIdx] = oldPath
    #         #     println("reverted")
    #         # end
    #     else
    #         newPaths[bIdx] = oldPath
    #         revert_solution!(solution, instance, [bundle], [oldPath], bunOldBins)
    #     end
    #     if !is_feasible(instance, solution)
    #         println("bundle $bundle")
    #         println("old path $oldPath and cost removed $costRemoved")
    #         println("new path $(newPath) and cost added $pathCost")
    #     end
    #     @assert is_feasible(instance, solution)

    #     # If a problem occurs in bundles on node synchronization, re-doing everything
    #     problem = false
    #     for bundle in instance.bundles
    #         for node in solution.bundlePaths[bundle.idx][2:end]
    #             if !(bundle.idx in solution.bundlesOnNode[node])
    #                 problem = true
    #                 break
    #             end
    #         end
    #     end
    #     if !problem
    #         for node in keys(solution.bundlesOnNode)
    #             for bunIdx in solution.bundlesOnNode[node]
    #                 if !(node in solution.bundlePaths[bunIdx][2:end])
    #                     problem = true
    #                     break
    #                 end
    #             end
    #         end
    #     end
    #     if problem
    #         @warn "Problem in bundles on node synchronization"
    #         # Emptying everything
    #         for node in keys(solution.bundlesOnNode)
    #             empty!(solution.bundlesOnNode[node])
    #         end
    #         # Refilling everything
    #         for bundle in instance.bundles
    #             for node in solution.bundlePaths[bundle.idx][2:end]
    #                 push!(solution.bundlesOnNode[node], bundle.idx)
    #             end
    #         end
    #     end

    #     # Checking bundles paths and bundles on nodes corresponds
    #     for bundle in instance.bundles
    #         for node in solution.bundlePaths[bundle.idx][2:end]
    #             if !(bundle.idx in solution.bundlesOnNode[node])
    #                 println("bundle $bundle")
    #                 println("old path $oldPath and cost removed $costRemoved")
    #                 println("new path $(newPaths[bIdx]) and cost added $pathCost")
    #                 println(
    #                     "node $node and bundles on node $(solution.bundlesOnNode[node])"
    #                 )
    #             end
    #             @assert bundle.idx in solution.bundlesOnNode[node]
    #         end
    #     end
    #     for node in keys(solution.bundlesOnNode)
    #         for bunIdx in solution.bundlesOnNode[node]
    #             if !(node in solution.bundlePaths[bunIdx][2:end])
    #                 println("bundle $bundle")
    #                 println("old path $oldPath and cost removed $costRemoved")
    #                 println("new path $path and cost added $pathCost")
    #                 println(
    #                     "node $node and bundles on node $(solution.bundlesOnNode[node])"
    #                 )
    #             end
    #             @assert node in solution.bundlePaths[bunIdx][2:end]
    #         end
    #     end
    # end

    # If no improvement at the end, reverting solution to its first state
    if improvement > 1e2
        println("Reverting solution because no improvement was found")
        @assert is_feasible(instance, prevSol)
        newPaths = deepcopy(solution.bundlePaths)
        revert_solution!(
            solution,
            instance,
            instance.bundles,
            prevSol.bundlePaths,
            prevSol.bins,
            newPaths,
        )
        println("Reverted solution")

        # revert_solution!(solution, instance, twoNodeBundles, oldPaths, oldBins, newPaths)

        # # Checking bundles paths and bundles on nodes corresponds
        # for bundle in instance.bundles
        #     for node in solution.bundlePaths[bundle.idx][2:end]
        #         @assert bundle.idx in solution.bundlesOnNode[node]
        #     end
        # end
        # for node in keys(solution.bundlesOnNode)
        #     for bunIdx in solution.bundlesOnNode[node]
        #         if !(node in solution.bundlePaths[bunIdx][2:end])
        #             println("bundle $bundle")
        #             localIdx = findfirst(x -> x == bunIdx, twoNodeBundleIdxs)
        #             println("old path $(oldPaths[localIdx])")
        #             println("new path $(newPaths[localIdx])")
        #             println(
        #                 "node $node and bundles on node $(solution.bundlesOnNode[node])"
        #             )
        #         end
        #         @assert node in solution.bundlePaths[bunIdx][2:end]
        #     end
        # end
        @assert is_feasible(instance, solution)

        return 0.0
    else
        return improvement
    end
end

function two_node_perturbation!(
    solution::Solution,
    instance::Instance,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int};
    costThreshold::Float64=EPS,
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    twoNodeBundleIdxs = get_bundles_to_update(instance, solution, src, dst)
    twoNodeBundles = instance.bundles[twoNodeBundleIdxs]
    # If there is no bundles concerned, returning
    length(twoNodeBundles) == 0 && return 0.0
    oldPaths = get_paths_to_update(solution, twoNodeBundles, src, dst)

    # The filtering could also occur in terms of cost removed : it must be above a certain threshold
    sum(
        bundle_estimated_removal_cost(bundle, path, instance, solution) for
        (bundle, path) in zip(twoNodeBundles, oldPaths)
    ) <= costThreshold && return 0.0

    # TODO : the bins ro be saved can be optimized once the whole thing is working
    # Saving previous solution and removing bundles
    @assert is_feasible(instance, solution)
    prevSol = solution_deepcopy(solution, instance)
    costRemoved = update_solution!(
        solution, instance, twoNodeBundles, oldPaths; remove=true
    )

    # TODO : remove this and test
    # If the cost removed only amouts to the linear part of the cost, improvements are too small compared to the computational cost
    pathsLinearCost = sum(
        bundle_path_linear_cost(bundle, path, TTGraph) for
        (bundle, path) in zip(twoNodeBundles, oldPaths)
    )
    if costRemoved + pathsLinearCost >= -EPS
        revert_solution!(solution, instance, twoNodeBundles, oldPaths, oldBins)
        @assert is_feasible(instance, solution)
        return 0.0
    end

    # Creating a unique bundle for all the bundles concerned
    commonBundle = fuse_bundles(instance, twoNodeBundles)

    # Inserting it back
    newPath, pathCost = greedy_insertion(
        solution,
        TTGraph,
        TSGraph,
        commonBundle,
        src,
        dst,
        CAPACITIES;
        sorted=true,
        findSources=false,
    )
    print(".")

    # Updating solution for the next step
    newPaths = [newPath for _ in 1:length(twoNodeBundles)]
    updateCost = update_solution!(solution, instance, twoNodeBundles, newPaths; sorted=true)
    improvement = updateCost + costRemoved
    @assert is_feasible(instance, solution)

    # Then re-introducing each bundle concerned by this perturbation
    for (i, bundleIdx) in enumerate(twoNodeBundleIdxs)
        bundle = instance.bundles[bundleIdx]
        improvement += bundle_reintroduction!(
            solution, instance, bundle, CAPACITIES; sorted=true, costThreshold=0.0
        )
        print(".")
    end
    @assert is_feasible(instance, solution)

    # If no improvement at the end, reverting solution to its first state
    if improvement > 1e1
        println("Reverting solution because no improvement was found")
        @assert is_feasible(instance, prevSol)
        newPaths = deepcopy(solution.bundlePaths)
        revert_solution!(
            solution,
            instance,
            instance.bundles,
            prevSol.bundlePaths,
            prevSol.bins,
            newPaths,
        )
        println("Reverted solution")
        @assert is_feasible(instance, solution)
        return 0.0
    else
        println(" total $(round(improvement, digits=1)) ")
        return improvement
    end
end

# Remove and insert back all bundles flowing from src to dst on the same path
function two_node_together!(
    solution::Solution,
    instance::Instance,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int};
    costThreshold::Float64=EPS,
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    twoNodeBundleIdxs = get_bundles_to_update(instance, solution, src, dst)
    twoNodeBundles = instance.bundles[twoNodeBundleIdxs]
    # If there is no bundles concerned, returning
    length(twoNodeBundles) == 0 && return 0.0
    @assert is_feasible(instance, solution)
    oldPaths = get_paths_to_update(solution, twoNodeBundles, src, dst)

    # The filtering could also occur in terms of cost removed : it must be above a certain threshold
    sum(
        bundle_estimated_removal_cost(bundle, path, instance, solution) for
        (bundle, path) in zip(twoNodeBundles, oldPaths)
    ) <= costThreshold && return 0.0

    # Saving previous bins and removing bundle 
    oldBins = save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, twoNodeBundles, oldPaths)
    )
    costRemoved = update_solution!(
        solution, instance, twoNodeBundles, oldPaths; remove=true
    )

    # If the cost removed only amouts to the linear part of the cost, improvements are too small compared to the computational cost
    pathsLinearCost = sum(
        bundle_path_linear_cost(bundle, path, TTGraph) for
        (bundle, path) in zip(twoNodeBundles, oldPaths)
    )
    if costRemoved + pathsLinearCost >= -EPS
        revert_solution!(solution, instance, twoNodeBundles, oldPaths, oldBins)
        @assert is_feasible(instance, solution)
        return 0.0
    end

    # Creating a unique bundle for all the bundles concerned
    # Putting one order for each delivery date to fuse them together
    newOrders = [Order(UInt(0), i) for i in 1:(instance.timeHorizon)]
    for bundle in twoNodeBundles
        # Fusing all orders
        for order in bundle.orders
            append!(newOrders[order.deliveryDate].content, order.content)
        end
    end
    filter!(o -> length(o.content) > 0, newOrders)
    for order in newOrders
        sort!(order.content)
    end
    newOrders = [
        add_properties(order, tentative_first_fit, CAPACITIES) for order in newOrders
    ]
    bunIdx = twoNodeBundleIdxs[1]
    commonBundle = Bundle(
        twoNodeBundles[1].supplier,
        twoNodeBundles[1].customer,
        newOrders,
        bunIdx,
        UInt(0),
        0,
        0,
    )

    # Inserting it back
    newPath, pathCost = greedy_insertion(
        solution,
        TTGraph,
        TSGraph,
        commonBundle,
        src,
        dst,
        CAPACITIES;
        sorted=true,
        findSources=false,
    )
    commonPaths = [newPath for _ in 1:length(twoNodeBundles)]
    update_solution!(solution, instance, twoNodeBundles, commonPaths; sorted=true)

    # Some new path parts can render the whole bundle path non-admissible
    # for bundle in twoNodeBundles
    #     if !is_path_admissible(TTGraph, solution.bundlePaths[bundle.idx])
    #         revert_solution!(
    #             solution, instance, twoNodeBundles, oldPaths, oldBins, commonPaths
    #         )
    #         @assert is_feasible(instance, solution)
    #         return 0.0
    #     end
    # end

    # Updating path if it improves the cost (accounting for EPS cost on arcs)
    if pathCost + costRemoved < -1e-3
        # Adding to solution
        @assert is_feasible(instance, solution)
        return pathCost + costRemoved
    else
        revert_solution!(solution, instance, twoNodeBundles, oldPaths, oldBins)
        @assert is_feasible(instance, solution)
        return 0.0
    end
end

# TODO : things that could be done also is to reintroduce bundles, than two node same path than reintroduce bundles
# than two node oncremental than bin pack improv
# This needs testing to see if the added computation time is worth it

function local_search!(
    solution::Solution,
    instance::Instance;
    twoNode::Bool=false,
    timeLimit::Int=300,
    firstLoop::Bool=false,
)
    # Combine the three small neighborhoods
    TTGraph = instance.travelTimeGraph
    sort_order_content!(instance)
    startCost = compute_cost(instance, solution)
    totalImprovement = 0.0

    # First, bundle reintroduction to change whole paths
    startTime = time()
    bundleIdxs = randperm(length(instance.bundles))
    bunCounter = 0
    print("Bundle reintroduction progress : ")
    percentIdx = ceil(Int, length(bundleIdxs) / 100)
    threshold = 5e-5 * startCost
    CAPACITIES = Int[]
    # The first loop is optional
    if firstLoop
        for (i, bundleIdx) in enumerate(bundleIdxs)
            bundle = instance.bundles[bundleIdx]
            improvement = bundle_reintroduction!(
                solution, instance, bundle, CAPACITIES; sorted=true, costThreshold=threshold
            )
            i % 10 == 0 && print("|")
            i % percentIdx == 0 && print(" $(round(Int, i * 100 / length(bundleIdxs)))% ")
            # loopImprovement += improvement
            totalImprovement += improvement
            improvement < -1e-3 && (bunCounter += 1)
            time() - startTime > timeLimit && break
        end
    end
    println()
    feasible = is_feasible(instance, solution)
    @info "Total bundle re-introduction improvement" :bundles_updated = bunCounter :improvement =
        totalImprovement :time = round((time() - startTime) * 1000) / 1000 :feasible =
        feasible

    # Two node gains things but takes a lot of time
    # Do multiple bundle reintroduction and then two node incremental : not very efficient
    # loopImprovement = -1e4
    # while time() - startTime < timeLimit && loopImprovement < -1e3
    #     loopImprovement = 0.0
    # for (i, bundleIdx) in enumerate(bundleIdxs)
    #     bundle = instance.bundles[bundleIdx]
    #     improvement = bundle_reintroduction!(
    #         solution, instance, bundle, CAPACITIES; sorted=true, costThreshold=threshold
    #     )
    #     i % 10 == 0 && print("|")
    #     i % percentIdx == 0 && print(" $(round(Int, i * 100 / length(bundleIdxs)))% ")
    #     # loopImprovement += improvement
    #     totalImprovement += improvement
    #     improvement < -1e-3 && (bunCounter += 1)
    #     time() - startTime > timeLimit && break
    # end
    # #     println()
    # # end
    # println()
    # feasible = is_feasible(instance, solution)
    # @info "Total bundle re-introduction improvement" :bundles_updated = bunCounter :improvement =
    #     totalImprovement :time = round((time() - startTime) * 1000) / 1000 :feasible =
    #     feasible

    # Second, two node incremental to optimize shared network
    startTime = time()
    twoNodeImprovement = 0.0
    twoNodeCounter = 0
    twoNodeTested = 0
    plantNodes = findall(x -> x.type == :plant, TTGraph.networkNodes)
    two_node_nodes = vcat(TTGraph.commonNodes, plantNodes)
    threshold = 5e-5 * compute_cost(instance, solution)
    i = 0
    percentIdx = ceil(Int, length(two_node_nodes) * length(TTGraph.commonNodes) / 100)
    barIdx = ceil(Int, percentIdx / 5)
    println("Two node common incremental progress : (| = $barIdx combinations)")

    for _ in 1:1
        for dst in shuffle(two_node_nodes), src in TTGraph.commonNodes
            i += 1
            i % percentIdx == 0 && print(
                " $(round(Int, i * 100 / (length(two_node_nodes) * length(TTGraph.commonNodes))))% ",
            )
            i % barIdx == 0 && print("|")
            are_nodes_candidate2(TTGraph, src, dst) || continue

            if twoNodePerturb
                improvement = two_node_common_incremental!(
                    solution, instance, src, dst, CAPACITIES; costThreshold=threshold
                )
            else
                improvement = two_node_common!(
                    solution, instance, src, dst, CAPACITIES; costThreshold=threshold
                )
            end

            twoNodeTested += 1
            (improvement < -1e-1) && (twoNodeCounter += 1)
            twoNodeImprovement += improvement
            totalImprovement += improvement
            round((time() - startTime) * 1000) / 1000 > timeLimit && break
        end
        println()
    end

    @info "Total two-node improvement" :couples_computed = twoNodeTested :improved =
        twoNodeCounter :improvement = twoNodeImprovement :time =
        round((time() - startTime) * 1000) / 1000

    # Again reintroduction
    # print("Bundle reintroduction progress : ")
    # bundleIdxs = randperm(length(instance.bundles))
    # percentIdx = ceil(Int, length(bundleIdxs) / 100)
    # threshold = 5e-5 * startCost
    # CAPACITIES = Int[]
    # reintroImprov = 0.0
    # startTime = time()
    # for (i, bundleIdx) in enumerate(bundleIdxs)
    #     bundle = instance.bundles[bundleIdx]
    #     improvement = bundle_reintroduction!(
    #         solution, instance, bundle, CAPACITIES; sorted=true, costThreshold=threshold
    #     )
    #     i % 10 == 0 && print("|")
    #     i % percentIdx == 0 && print(" $(round(Int, i * 100 / length(bundleIdxs)))% ")
    #     totalImprovement += improvement
    #     reintroImprov += improvement
    #     improvement < -1e-3 && (bunCounter += 1)
    #     time() - startTime > timeLimit && break
    # end
    # println()
    # feasible = is_feasible(instance, solution)
    # @info "Total bundle re-introduction improvement" :bundles_updated = bunCounter :improvement =
    #     reintroImprov :time = round((time() - startTime) * 1000) / 1000 :feasible = feasible

    # Second, two node incremental to optimize shared network
    # if twoNode
    startTime = time()
    twoNodeImprovement = 0.0
    twoNodeCounter = 0
    twoNodeTested = 0
    plantNodes = findall(x -> x.type == :plant, TTGraph.networkNodes)
    two_node_nodes = vcat(TTGraph.commonNodes, plantNodes)
    # threshold = 1e-4 * startCost
    i = 0
    percentIdx = ceil(Int, length(two_node_nodes) * length(TTGraph.commonNodes) / 100)
    barIdx = ceil(Int, percentIdx / 5)
    # println("1% equals $percentIdx tuples of nodes tests")
    println("Two node incremental progress : (| = $barIdx combinations)")
    for dst in shuffle(two_node_nodes), src in TTGraph.commonNodes
        i += 1
        i % percentIdx == 0 && print(
            " $(round(Int, i * 100 / (length(two_node_nodes) * length(TTGraph.commonNodes))))% ",
        )
        i % barIdx == 0 && print("|")
        are_nodes_candidate(TTGraph, src, dst) || continue
        improvement = two_node_incremental!(
            solution, instance, src, dst, CAPACITIES; sorted=true, costThreshold=threshold
        )
        twoNodeTested += 1
        (improvement < -1e-1) && (twoNodeCounter += 1)
        twoNodeImprovement += improvement
        totalImprovement += improvement
        round((time() - startTime) * 1000) / 1000 > timeLimit && break
    end
    println()
    @info "Total two-node improvement" :couples_computed = twoNodeTested :improved =
        twoNodeCounter :improvement = twoNodeImprovement :time =
        round((time() - startTime) * 1000) / 1000
    # end
    reintroImprov = 0.0

    # Bundle reintroduction at last 
    print("Bundle reintroduction progress : ")
    bundleIdxs = randperm(length(instance.bundles))
    percentIdx = ceil(Int, length(bundleIdxs) / 100)
    threshold = 5e-5 * compute_cost(instance, solution)
    CAPACITIES = Int[]
    reintroImprov = 0.0
    startTime = time()
    for (i, bundleIdx) in enumerate(bundleIdxs)
        bundle = instance.bundles[bundleIdx]
        improvement = bundle_reintroduction!(
            solution, instance, bundle, CAPACITIES; sorted=true, costThreshold=threshold
        )
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i * 100 / length(bundleIdxs)))% ")
        totalImprovement += improvement
        reintroImprov += improvement
        improvement < -1e-3 && (bunCounter += 1)
        time() - startTime > timeLimit && break
    end
    println()
    feasible = is_feasible(instance, solution)
    @info "Total bundle re-introduction improvement" :bundles_updated = bunCounter :improvement =
        reintroImprov :time = round((time() - startTime) * 1000) / 1000 :feasible = feasible

    # Finally, bin packing improvement to optimize packings
    startTime = time()
    improvement = bin_packing_improvement!(solution, instance; sorted=true)
    @info "Bin packing improvement" :improvement = improvement :time =
        round((time() - startTime) * 1000) / 1000
    totalImprovement += improvement
    @info "Full local search step done" :total_improvement = totalImprovement
    return totalImprovement
end