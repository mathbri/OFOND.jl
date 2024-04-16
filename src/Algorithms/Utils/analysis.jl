# Algorithms analysis functions

# Mostly used to identify / quantify the most promosing operations in the different algorithms
# To be used with @time or @profile or @profile_alloc

function lower_bound_insertion_analysis(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
)
    recomputed, giantBetter, giantDiff = false, true, 0.0
    update_cost_matrix!(
        solution,
        TTGraph,
        TSGraph,
        bundle;
        sorted=sorted,
        use_bins=true,
        current_cost=current_cost,
    )
    pathCostMatrix = deepcopy(TTGraph.costMatrix)
    shortestPath, pathCost = lower_bound_path(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        src,
        dst;
        use_bins=true,
        current_cost=false,
        giant=true,
    )
    # If the path is not admissible, re-computing it
    if !is_path_admissible(TTGraph, shortestPath)
        recomputed = true
        shortestPath1, pathCost1 = lower_bound_path(
            solution,
            TTGraph,
            TSGraph,
            bundle,
            src,
            dst;
            use_bins=false,
            current_cost=false,
            giant=false,
        )
        pathCost1 = get_path_cost(shortestPath1, pathCostMatrix)
        shortestPath2, pathCost2 = lower_bound_path(
            solution,
            TTGraph,
            TSGraph,
            bundle,
            src,
            dst;
            use_bins=false,
            current_cost=false,
            giant=true,
        )
        pathCost2 = get_path_cost(shortestPath2, pathCostMatrix)
        giantDiff = pathCost2 - pathCost1
        if pathCost1 < pathCost2 && is_path_admissible(TTGraph, shortestPath1)
            shortestPath, pathCost = shortestPath1, pathCost1
            giantBetter = false
        else
            shortestPath, pathCost = shortestPath2, pathCost2
            giantBetter = true
            giantDiff > 0 && (giantDiff = 0.0)
        end
    end
    return shortestPath, pathCost, recomputed, giantBetter, giantDiff
end

function greedy_insertion_analysis(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
)
    recomputed, binUsedBetter, binUsedDiff = false, true, 0.0
    shortestPath, pathCost = greedy_path(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        src,
        dst;
        sorted=true,
        use_bins=true,
        current_cost=false,
    )
    # If the path is not admissible, re-computing it
    if !is_path_admissible(TTGraph, shortestPath)
        recomputed = true
        # First trying to halve cost for the path computation
        costMatrix = deepcopy(TTGraph.costMatrix)
        shortestPath1, pathCost = greedy_path(
            solution,
            TTGraph,
            TSGraph,
            bundle,
            src,
            dst;
            sorted=true,
            use_bins=true,
            opening_factor=0.5,
            current_cost=false,
        )
        pathCost1 = get_path_cost(shortestPath1, costMatrix)
        # Then not taking into account the current solution
        shortestPath2, pathCost = greedy_path(
            solution,
            TTGraph,
            TSGraph,
            bundle,
            src,
            dst;
            sorted=true,
            use_bins=false,
            current_cost=false,
        )
        pathCost2 = get_path_cost(shortestPath2, costMatrix)
        binUsedDiff = pathCost2 - pathCost1
        if pathCost1 < pathCost2 && is_path_admissible(TTGraph, shortestPath1)
            shortestPath, pathCost = shortestPath1, pathCost1
            binUsedBetter = true
        else
            shortestPath, pathCost = shortestPath2, pathCost2
            binUsedBetter = false
            binUsedDiff > 0 && (binUsedDiff = 0.0)
        end
    end
    return shortestPath, pathCost, recomputed, binUsedBetter, binUsedDiff
end

function greedy_analysis(solution::Solution, instance::Instance; shuffle::Bool=false)
    sol, inst = deepcopy(solution), deepcopy(instance)
    TTGraph, TSGraph = inst.travelTimeGraph, inst.timeSpaceGraph
    recomputedCount, binUsedBetterCount = 0, 0
    binUsedBetterDiff, binNotUsedBetterDiff = 0.0, 0.0
    # Sorting commodities in orders and bundles between them
    sort_order_content!(inst)
    sortedBundleIdxs = if !shuffle
        sortperm(bundles; by=bun -> bun.maxPackSize, rev=true)
    else
        randperm(length(bundles))
    end
    # Computing the greedy delivery possible for each bundle
    for bundleIdx in sortedBundleIdxs
        bundle = inst.bundles[bundleIdx]

        # Retrieving bundle start and end nodes
        suppNode = TTGraph.bundleStartNodes[bundleIdx]
        custNode = TTGraph.bundleEndNodes[bundleIdx]
        # Computing shortest path
        shortestPath, pathCost, recomputed, binUsedBetter, binUsedDiff = greedy_insertion_analysis(
            sol, TTGraph, TSGraph, bundle, suppNode, custNode
        )

        recomputedCount += recomputed ? 1 : 0
        binUsedBetterCount += binUsedBetter ? 1 : 0
        binUsedBetterDiff += binUsedBetter ? binUsedDiff : 0
        binNotUsedBetterDiff += binUsedBetter ? 0 : binUsedDiff

        # Adding path to solution
        remove_shotcuts!(shortestPath, travelTimeGraph)
        add_path!(sol, bundle, shortestPath)
        # Updating the bins for each order of the bundle
        for order in bundle.orders
            update_bins!(sol, TSGraph, TTGraph, shortestPath, order; sorted=true)
        end
    end
    println("Solution cost : $(compute_cost(inst, sol))")
    println("Recomputed count: $recomputedCount")
    println("Bin used better count: $binUsedBetterCount")
    println(
        "Bin used better diff: $binUsedBetterDiff (mean diff: $(binUsedBetterDiff/binUsedBetterCount))",
    )
    binNotUsedBetterCount = recomputedCount - binUsedBetterCount
    println(
        "Bin not used better diff: $binNotUsedBetterDiff (mean diff: $(binNotUsedBetterDiff/binNotUsedBetterCount))",
    )

    return sol, inst
end

function greedy_shuffle_analysis(solution::Solution, instance::Instance; n_iter::Int=10)
    meancost = 0.0
    for _ in 1:n_iter
        sol, inst = greedy_analysis(solution, instance; shuffle=true)
        meancost += compute_cost(inst, sol)
    end
    meancost /= n_iter
    return println("Mean cost: $meancost")
end

# Running bin packing improvement with analysis logging and no change in data
function packing_recomputation_analysis!(sol::Solution, inst::Instance)
    costImprov = 0.0
    oneBinCount, linearCount, boudReachedCount = 0, 0, 0
    bfdBetterCount, bfdSavedBins, newBetterCount = 0, 0, 0
    ffdBinSavedCount = 0
    for arc in edges(inst.timeSpaceGraph)
        arcBins = sol.bins[src(arc), dst(arc)]
        # If there is no bins, one bin or the arc is linear, skipping arc
        if length(arcBins) <= 1
            oneBinCount += 1
            continue
        end
        arcData = timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        if arcData.isLinear
            linearCount += 1
            continue
        end
        # If there is no gap with the lower bound, skipping arc
        arcVolume = sum(arcData.capacity - bin.capacity for bin in arcBins)
        if ceil(arcVolume / arcData.capacity) == length(arcBins)
            boudReachedCount += 1
            continue
        end
        # Gathering all commodities
        allCommodities = reduce(vcat, arcBins)
        # Computing new bins
        newBins = first_fit_decreasing(
            Bin[], arcData.capacity, allCommodities; sorted=sorted
        )
        bfdBins = best_fit_decreasing(
            Bin[], arcData.capacity, allCommodities; sorted=sorted
        )
        if length(newBins) > length(bfdBins)
            bfdSavedBins = length(newBins) - length(bfdBins)
            newBins = bfdBins
            bfdBetterCount += 1
        else
            ffdBinSavedCount += length(bfdBins) - length(newBins)
        end
        # If the number of bins dir not change, skipping next
        if length(newBins) >= length(arcBins)
            continue
        end
        newBetterCount += 1
        # Computing cost improvement
        costImprov +=
            (arcData.unitCost + arcData.carbonCost) * (length(arcBins) - length(newBins))
        # Updating bins
        sol.bins[src(arc), dst(arc)] = newBins
    end
    println("One bin count: $oneBinCount")
    println("Linear count: $linearCount")
    println("Bound reached count: $boudReachedCount")
    println("Best fit decrease better count: $bfdBetterCount")
    println("Best fit decrease saved bins: $bfdSavedBins")
    println("First fit decrease saved bins: $ffdBinSavedCount")
    println("New better count: $newBetterCount")
    return costImprov
end

function bundle_reintroduction_analysis!(sol::Solution, inst::Instance)
    costImprov = 0.0
    negCostRemCount, noImprovCount, samePathCount = 0, 0, 0
    lbBetterCount = 0
    greedyImprov, lbImprov = 0.0, 0.0
    recomputedCountG, binUsedBetterCount = 0, 0
    binUsedBetterDiff, binNotUsedBetterDiff = 0.0, 0.0
    recomputedCountLB, giantBetterCount = 0, 0
    giantBetterDiff, giantNotBetterDiff = 0.0, 0.0

    for bundle in inst.bundles
        TTGraph, TSGraph = inst.travelTimeGraph, inst.timeSpaceGraph
        bundles, paths = [bundle], [sol.bundlePaths[bundle.idx]]
        # Saving previous solution state 
        previousBins, costRemoved = save_and_remove_bundle!(
            sol, TSGraph, TTGraph, bundles, paths; current_cost=false
        )
        # If the cost removed is negative or null, no chance of improving 
        if costRemoved <= 0
            negCostRemCount += 1
            # Reverting bins to the previous state
            revert_bins!(sol, previousBins)
            continue
        end
        # Inserting it back
        suppNode = TTGraph.bundleStartNodes[bundle.idx]
        custNode = TTGraph.bundleEndNodes[bundle.idx]

        # Computing shortest path
        bestCost, bestPath, recomputedG, binUsedBetter, binUsedDiff = greedy_insertion_analysis(
            sol, TTGraph, TSGraph, bundle, suppNode, custNode
        )
        lbPath, lbCost, recomputedLB, giantBetter, giantDiff = lower_bound_insertion_analysis(
            solution, TTGraph, TSGraph, bundle, suppNode, custNode
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
        if bestCost > lbCost
            lbBetterCount += 1
            pathCost < costRemoved && (lbImprov += costRemoved - pathCost)
            bestCost, bestPath = lbCost, lbPath
            recomputedCountG += recomputedG ? 1 : 0
            binUsedBetterCount += binUsedBetter ? 1 : 0
            binUsedBetterDiff += binUsedBetter ? binUsedDiff : 0
            binNotUsedBetterDiff += binUsedBetter ? 0 : binUsedDiff
        else
            recomputedCountLB += recomputedLB ? 1 : 0
            giantBetterCount += giantBetter ? 1 : 0
            giantBetterDiff += giantBetter ? giantDiff : 0
            giantNotBetterDiff += giantBetter ? 0 : giantDiff
            pathCost < costRemoved && (greedyImprov += costRemoved - pathCost)
        end

        # Updating path if it improves the cost
        if pathCost < costRemoved
            costImprov += costRemoved - pathCost
            remove_path!(sol, bundle)
            # Adding path to solution
            remove_shotcuts!(bestPath, travelTimeGraph)
            add_path!(sol, bundle, bestPath)
            # Updating the bins for each order of the bundle
            for order in bundle.orders
                update_bins!(sol, TSGraph, TTGraph, bestPath, order; sorted=true)
            end
        else
            noImprovCount += 1
            sol.bundlePaths[bundle.idx] == bestPath && samePathCount += 1
            revert_bins!(sol, previousBins)
        end
    end
    println("\nCost improvement : $costImprov (LB: $lbImprov, Greedy: $greedyImprov)")
    println("LB better count: $lbBetterCount")
    println("Negative cost removed count: $negCostRemCount")
    println("No improvement count: $noImprovCount")
    println("Same path count: $samePathCount")
    println("\nGreedy insertion")
    println("Recomputed count: $recomputedCountG")
    println("Bin used better count: $binUsedBetterCount")
    println(
        "Bin used better diff: $binUsedBetterDiff (mean diff: $(binUsedBetterDiff/binUsedBetterCount))",
    )
    binNotUsedBetterCount = recomputedCountG - binUsedBetterCount
    println(
        "Bin not used better diff: $binNotUsedBetterDiff (mean diff: $(binNotUsedBetterDiff/binNotUsedBetterCount))",
    )
    println("\nLower Bound insertion")
    println("Recomputed count: $recomputedCountLB")
    println("Giant better count: $giantBetterCount")
    println(
        "Giant better diff: $giantBetterDiff (mean diff: $(giantBetterDiff/giantBetterCount))",
    )
    giantNotBetterCount = recomputedCountLB - binUsedBetterCount
    println(
        "Giant not better diff: $giantNotBetterDiff (mean diff: $(giantNotBetterDiff/giantNotBetterCount))",
    )
    println()
    return costImprov
end

function two_node_incremental_analysis!(sol::Solution, inst::Instance)
    # TODO
end

# Do this process for the whole local search instead of single functions ?
# Actually modify solution but deepcopy it at the start

function local_search_analysis(solution::Solution, instance::Instance; n_iter::Int=3)
    sol, inst = deepcopy(solution), deepcopy(instance)
    sort_order_content!(inst)

    totalCostImprov = 0.0

    for i in 1:n_iter
        println("\nIteration: $i\n")
        println("Bundle reintroduction :")
        costImprov = bundle_reintroduction_analysis!(sol, inst)
        println("Two node incremental :")
        costImprov += two_node_incremental_analysis!(sol, inst)
        println("Packing recomputation :")
        costImprov += packing_recomputation_analysis!(sol, inst)
        totalCostImprov += costImprov
        if costImprov <= EPS
            break
        end
    end
    println("Total Cost improvement : $totalCostImprov")

    return totalCostImprov
end