# Algorithms analysis functions

# Mostly used to identify / quantify the most promosing operations in the different algorithms
# To be used with @time or @profile or @profile_alloc

# First analysis would be to check whether things happen
global RECOMPUTATION, NEVER_ADMISSIBLE, COST_INCREASE = 0, 0, 0.0
# Then if it happens a lot, a deeper analysis may be neededs
# Maybe writing logs in csv file would ease the analysis so that it can be done in a notebook

function greedy_insertion_analysis(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
)
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
        global RECOMPUTATION += 1
        # First trying to halve cost for the path computation
        costMatrix = deepcopy(TTGraph.costMatrix)
        shortestPath1, pathCost1 = greedy_path(
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
        pathCost1 = get_path_cost(shortestPath1, costMatrix)
        global COST_INCREASE += pathCost1 - pathCost
        is_path_admissible(TTGraph, shortestPath1) || (global NEVER_ADMISSIBLE += 1)
        return shortestPath1, pathCost1
    end
    return shortestPath, pathCost
end

function greedy_analysis(solution::Solution, instance::Instance; shuffle::Bool=false)
    println("\nGreedy analysis :")
    sol, inst = deepcopy(solution), deepcopy(instance)
    global RECOMPUTATION, NEVER_ADMISSIBLE, COST_INCREASE = 0, 0, 0.0
    TTGraph, TSGraph = inst.travelTimeGraph, inst.timeSpaceGraph
    # Sorting commodities in orders and bundles between them
    sort_order_content!(inst)
    sortedBundleIdxs = if !shuffle
        sortperm(bundles; by=bun -> bun.maxPackSize, rev=true)
    else
        randperm(length(bundles))
    end
    # Computing the greedy delivery possible for each bundle
    cost = 0.0
    for bundleIdx in sortedBundleIdxs
        bundle = inst.bundles[bundleIdx]
        # Retrieving bundle start and end nodes
        suppNode = TTGraph.bundleStartNodes[bundleIdx]
        custNode = TTGraph.bundleEndNodes[bundleIdx]
        # Computing shortest path
        shortestPath, pathCost = greedy_insertion_analysis(
            sol, TTGraph, TSGraph, bundle, suppNode, custNode
        )
        # Adding path to solution
        cost += update_solution!(sol, inst, [bundle], [shortestPath]; sorted=true)
    end
    println("Solution cost : $cost")
    println(
        "Recomputations : $RECOMPUTATION done with $NEVER_ADMISSIBLE never admissible and a cost increase of $COST_INCREASE \n",
    )
    return sol, inst, cost
end

function greedy_shuffle_analysis(solution::Solution, instance::Instance; n_iter::Int=10)
    meanRecomp, meanNever, meanCostIncr, meanCost = 0.0
    for _ in 1:n_iter
        sol, inst, cost = greedy_analysis(solution, instance; shuffle=true)
        meancost += cost
        meanRecomp += RECOMPUTATION
        meanNever += NEVER_ADMISSIBLE
        meanCostIncr += COST_INCREASE
    end
    println("Mean cost: $(meancost / n_iter)")
    println("Mean recomputation: $(meanRecomp / n_iter)")
    println("Mean never admissible: $(meanNever / n_iter)")
    return println("Mean cost increase: $(meanCostIncr / n_iter) \n")
end

# Running bin packing improvement with analysis logging and no change in data
function packing_recomputation_analysis!(sol::Solution, inst::Instance)
    println("\nPacking recomputation analysis :")
    costImprov = 0.0
    counters = init_counters([
        "One Bin", "Linear", "Boud Reached", "BFD Better", "New Better"
    ])
    gapCounters = init_counters(["BFD Saved Bins", "FFD Saved Bins", "MILP Gap Bins"])
    for arc in edges(inst.timeSpaceGraph)
        arcBins = sol.bins[src(arc), dst(arc)]
        # If there is no bins, one bin or the arc is linear, skipping arc
        length(arcBins) <= 1 && (counters["One Bin"] += 1; continue)
        arcData = timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        arcData.isLinear && (counters["Linear"] += 1; continue)
        # If there is no gap with the lower bound, skipping arc
        arcCapa = arcData.capacity
        arcVolume = sum(arcCapa - bin.capacity for bin in arcBins)
        if ceil(arcVolume / arcCapa) == length(arcBins)
            counters["Boud Reached"] += 1
            continue
        end
        # Gathering all commodities
        allCommodities = reduce(vcat, arcBins)
        # Computing new bins
        newBins = first_fit_decreasing(Bin[], arcCapa, allCommodities; sorted=true)
        bfdBins = best_fit_decreasing(Bin[], arcCapa, allCommodities; sorted=true)
        gapCounters["FFD Saved Bins"] += max(0, length(arcBins) - length(newBins))
        gapCounters["BFD Saved Bins"] += max(0, length(arcBins) - length(bfdBins))
        if length(newBins) > length(bfdBins)
            newBins = bfdBins
            counters["BFD Better"] += 1
        end
        # If the number of bins did not change, skipping next
        savedBins = length(arcBins) - length(newBins)
        savedBins <= 0 && continue
        counters["New Better"] += 1
        milpBins = milp_packing(Bin[], arcData.capacity, allCommodities)
        gapCounters["MILP Gap Bins"] += max(0, length(newBins) - length(milpBins))
        # Computing cost improvement
        costImprov += arcData.unitCost * savedBins
        # Updating bins
        sol.bins[src(arc), dst(arc)] = newBins
    end
    println("Cost improvement with recomputation: $costImprov")
    print_counters(counters)
    print_counters(gapCounters)
    println()
    return costImprov
end

global RECOMPUTATION_LB, NEVER_ADMISSIBLE_LB, COST_INCREASE_LB = 0, 0, 0.0

function lower_bound_insertion_analysis(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
)
    update_cost_matrix!(
        solution, TTGraph, TSGraph, bundle; sorted=sorted, use_bins=true, current_cost=false
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
    pathCost = get_path_cost(shortestPath, pathCostMatrix)
    # If the path is not admissible, re-computing it
    if !is_path_admissible(TTGraph, shortestPath)
        global RECOMPUTATION_LB += 1
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
        global COST_INCREASE_LB += pathCost1 - pathCost
        is_path_admissible(TTGraph, shortestPath1) || (global NEVER_ADMISSIBLE_LB += 1)
        return shortestPath1, pathCost1
    end
    return shortestPath, pathCost
end

global NO_IMROV_POSSIBLE, NO_IMPROV_DONE = 0, 0
global LB_BETTER, LB_BETTER_DIFF, G_BETTER_DIFF = 0, 0.0, 0.0

function bundle_reintroduction_analysis!(solution::Solution, instance::Instance)
    println("\nBundle reintroduction analysis :")
    global RECOMPUTATION, NEVER_ADMISSIBLE, COST_INCREASE = 0, 0, 0.0
    global RECOMPUTATION_LB, NEVER_ADMISSIBLE_LB, COST_INCREASE_LB = 0, 0, 0.0
    global NO_IMPROV_DONE, NO_IMROV_POSSIBLE, LB_BETTER, LB_BETTER_DIFF, G_BETTER_DIFF = 0,
    0, 0, 0.0,
    0.0
    sol, inst = deepcopy(solution), deepcopy(instance)
    costImprov = 0.0
    bundleIdxs = randperm(length(inst.bundles))
    for bundleIdx in bundleIdxs
        bundle = inst.bundles[bundleIdx]
        TTGraph, TSGraph = inst.travelTimeGraph, inst.timeSpaceGraph
        bundles, paths = [bundle], [sol.bundlePaths[bundle.idx]]
        # Saving previous solution state 
        previousBins, costRemoved = save_and_remove_bundle!(
            sol, inst, bundles, paths; current_cost=false
        )
        # If the cost removed only amouts to the linear part of the cost, no chance of improving, at best the same cost
        pathsLinearCost = bundle_path_linear_cost(bundle, oldPaths[1], TTGraph)
        if costRemoved + pathsLinearCost >= -EPS
            global NO_IMROV_POSSIBLE += 1
            update_solution!(sol, inst, bundles, oldPaths; skipRefill=true)
            # Reverting bins to the previous state
            revert_bins!(sol, oldBins)
            continue
        end
        # Inserting it back
        suppNode = TTGraph.bundleStartNodes[bundle.idx]
        custNode = TTGraph.bundleEndNodes[bundle.idx]
        # Computing shortest path
        bestPath, bestCost = greedy_insertion_analysis(
            sol, TTGraph, TSGraph, bundle, suppNode, custNode
        )
        lbPath, lbCost = lower_bound_insertion_analysis(
            sol, TTGraph, TSGraph, bundle, suppNode, custNode
        )
        # Selecting the best one
        if greedyCost > lbCost
            global LB_BETTER += 1
            global LB_BETTER_DIFF += greedyCost - lbCost
            bestPath, bestCost = lbPath, lbCost
        else
            global G_BETTER_DIFF += lbCost - greedyCost
        end

        # Updating path if it improves the cost
        if bestCost + costRemoved < -EPS
            costImprov += costRemoved - pathCost
            update_solution!(sol, inst, bundles, [bestPath]; sorted=true)
        else
            global NO_IMPROV_DONE += 1
            update_solution!(sol, inst, bundles, oldPaths; skipRefill=true)
            # Reverting bins to the previous state
            revert_bins!(sol, oldBins)
        end
    end
    println("\nCost improvement : $costImprov")
    improvDone = length(bundleIdxs) - (NO_IMPROV_DONE + NO_IMROV_POSSIBLE)
    println(
        "Improvements : $improvDone done for $NO_IMROV_POSSIBLE not possible and $NO_IMPROV_DONE not improving",
    )
    println(
        "Insertion comparison : LB insertion better for $LB_BETTER insertions with difference of $LB_BETTER_DIFF and Greedy for $G_BETTER_DIFF",
    )
    println(
        "Greedy recomputations : $RECOMPUTATION done with $NEVER_ADMISSIBLE never admissible and a cost increase of $COST_INCREASE",
    )
    println(
        "Lower bound recomputations : $RECOMPUTATION_LB done with $NEVER_ADMISSIBLE_LB never admissible and a cost increase of $COST_INCREASE_LB \n",
    )
    return costImprov
end

# TODO : resume from here

# Create 3 solutions for the analysis : one with all greedy, one with best and one with all lower bound
function two_node_incremental_analysis!(sol::Solution, inst::Instance)
    costImprov = 0.0
    TTGraph, TSGraph = inst.travelTimeGraph, inst.timeSpaceGraph

    counters = init_counters([
        "No Improv",
        "Filtered",
        "No Bundles",
        "Src Plat",
        "Src Time",
        "Dst Plat",
        "Dst Time",
    ])
    greedyCounters = init_counters([
        "Improv", "Better", "Src Plat", "Src Time", "Dst Plat", "Dst Time", "Mean Bundles"
    ])
    mixCounters = init_counters([
        "Improv", "Better", "Src Plat", "Src Time", "Dst Plat", "Dst Time", "Mean Bundles"
    ])
    lbCounters = init_counters([
        "Improv", "Better", "Src Plat", "Src Time", "Dst Plat", "Dst Time", "Mean Bundles"
    ])

    for src in TTGraph.commonNodes, dst in TTGraph.commonNodes
        if !are_nodes_candidate(TTGraph, src, dst)
            src != dst && (counters["Filtered"] += 1)
            continue
        end
        twoNodeBundles = get_bundles_to_update(sol, src, dst)
        if length(twoNodeBundles) == 0
            counters["No Bundles"] += 1
            continue
        end
        twoNodePaths = get_paths_to_update(sol, twoNodeBundles, src, dst)
        # Saving previous solution state 
        previousBins, costRemoved = save_and_remove_bundle!(
            sol, inst, bundles, twoNodePaths; current_cost=current_cost
        )
        # Inserting it back
        mixSol, lbSol = deepcopy(sol), deepcopy(sol)
        gAddedCost, mixAddedCost, lbAddedCost = 0.0, 0.0, 0.0
        for bundle in twoNodeBundles
            # Computing shortest path
            gPath, gCost = greedy_insertion(sol, TTGraph, TSGraph, bundle, src, dst)
            bestPath, bestCost = best_reinsertion(
                mixSol, TTGraph, TSGraph, bundle, src, dst; current_cost=false
            )
            lbPath, lbCost = lower_bound_insertion(
                lbSol, TTGraph, TSGraph, bundle, src, dst; use_bins=true
            )
            # Computing real cost of lbPath
            update_cost_matrix!(sol, TTGraph, TSGraph, bundle; sorted=sorted, use_bins=true)
            lbCost = get_path_cost(lbPath, TTGraph.costMatrix)

            gAddedCost += gCost
            mixAddedCost += bestCost
            lbAddedCost += lbCost
            # Adding to solution
            update_solution!(sol, inst, [bundle], [gPath]; sorted=true)
            update_solution!(mixSol, inst, [bundle], [bestPath]; sorted=true)
            update_solution!(lbSol, inst, [bundle], [lbPath]; sorted=true)
        end

        minAddedCost = min(gAddedCost, mixAddedCost, lbAddedCost)
        counter_to_update, bestSol = greedyCounters, sol
        if lbAddedCost < mixAddedCost && lbAddedCost < gAddedCost
            counter_to_update, bestSol = lbCounters, lbSol
        elseif mixAddedCost < gAddedCost && mixAddedCost < lbAddedCost
            counter_to_update, bestSol = mixCounters, mixSol
        end

        if minAddedCost < costRemoved
            costImprov += costRemoved - minAddedCost
            counter_to_update["Improv"] += costImprov
            counter_to_update["Mean Bundles"] += length(twoNodeBundles)
            counter_to_update["Better"] += 1
            counter_to_update["Src Plat"] += is_platform(TTGraph, src)
            counter_to_update["Src Time"] += TTGraph.stepToDel[src]
            counter_to_update["Dst Plat"] += is_platform(TTGraph, dst)
            counter_to_update["Dst Time"] += TTGraph.stepToDel[dst]
            sol = bestSol
        end

        # Solution already updated so if it didn't improve, reverting to old state
        if minAddedCost > costRemoved
            counters["No Improv"] += 1
            update_solution!(
                sol, inst, twoNodeBundles, twoNodePaths; remove=true, skipRefill=true
            )
            return revert_bins!(sol, previousBins)
        end
    end

    return costImprov
end

# Do this process for the whole local search instead of single functions ?
# Actually modify solution but deepcopy it at the start

function local_search_analysis(solution::Solution, instance::Instance; n_iter::Int=3)
    sol, inst = deepcopy(solution), deepcopy(instance)
    sort_order_content!(inst)

    totalCostImprov = 0.0

    for i in 1:n_iter
        println("\nIteration: $i\n")
        iterCostImprov = 0.0
        println("Bundle reintroduction :")
        costImprov = bundle_reintroduction_analysis!(sol, inst)
        println("Cost improvement : $costImprov")
        iterCostImprov += costImprov
        println("Two node incremental :")
        costImprov = two_node_incremental_analysis!(sol, inst)
        println("Cost improvement : $costImprov")
        iterCostImprov += costImprov
        println("Packing recomputation :")
        costImprov = packing_recomputation_analysis!(sol, inst)
        println("Cost improvement : $costImprov")
        iterCostImprov += costImprov
        totalCostImprov += iterCostImprov
        iterCostImprov <= EPS && break
        println("Iteration Cost improvement : $iterCostImprov\n")
    end
    println("Total Cost improvement : $totalCostImprov")

    return totalCostImprov
end