# Algorithms analysis functions

# Mostly used to identify / quantify the most promosing operations in the different algorithms
# To be used with @time or @profile or @profile_alloc

# TODO : adapt to update_solution 

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
    return shortestPath, pathCost, recomputed, giantBetter, round(Int, giantDiff)
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
    return shortestPath, pathCost, recomputed, binUsedBetter, round(Int, binUsedDiff)
end

function update_counters!(
    counters::Dict{String,Int},
    recomputed::Bool,
    binUsedBetter::Bool,
    binUsedDiff::Float64;
    lowerBound::Bool=false,
)
    prefix = "Bin"
    lowerBound && (prefix = "Giant")
    recomputed && counters["Recomputed"] += 1
    binUsedBetter && counters["$prefix Used Better"] += 1
    if binUsedBetter
        counters["$prefix Used Diff"] += binUsedDiff
    else
        counters["$prefix Not Used Diff"] += binUsedDiff
    end
end

function greedy_analysis(solution::Solution, instance::Instance; shuffle::Bool=false)
    sol, inst = deepcopy(solution), deepcopy(instance)
    TTGraph, TSGraph = inst.travelTimeGraph, inst.timeSpaceGraph
    counters = init_counters([
        "Recomputed", "Bin Used Better", "Bin Used Diff", "Bin Not Used Diff"
    ])
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

        update_counters!(counters, recomputed, binUsedBetter, binUsedDiff)

        # Adding path to solution
        update_solution!(sol, inst, [bundle], [shortestPath]; sorted=true)
    end
    println("Solution cost : $(compute_cost(inst, sol))")
    counters["Bin Used Mean Diff"] = counters["Bin Used Diff"] / counters["Bin Used Better"]
    binNotUsedBetter = counters["Recomputed"] - counters["Bin Used Better"]
    counters["Bin Not Used Mean Diff"] = counters["Bin Not Used Diff"] / binNotUsedBetter
    print_counters(counters)

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
    return costImprov
end

function bundle_reintroduction_analysis!(sol::Solution, inst::Instance)
    costImprov = 0.0

    counters = init_counters(["Negative Removal", "No Improv", "Same Path", "LB Better"])
    greedyCounters = init_counters([
        "Recomputed", "Bin Used Better", "Bin Used Diff", "Bin Not Used Diff"
    ])
    lbCounters = init_counters([
        "Recomputed", "Giant Used Better", "Giant Used Diff", "Giant Not Used Diff"
    ])
    improvCharac = init_counters([
        "Total", "Greedy", "LB", "On Direct", "Mean Orders", "Mean Commo", "Mean Volume"
    ])

    for bundle in inst.bundles
        TTGraph, TSGraph = inst.travelTimeGraph, inst.timeSpaceGraph
        bundles, paths = [bundle], [sol.bundlePaths[bundle.idx]]
        # Saving previous solution state 
        previousBins, costRemoved = save_and_remove_bundle!(
            sol, TSGraph, TTGraph, bundles, paths; current_cost=false
        )
        # If the cost removed is negative or null, no chance of improving 
        if costRemoved <= 0
            counters["Negative Removal"] += 1
            update_solution!(solution, instance, bundles, paths; skipRefill=true)
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
            solution, TTGraph, TSGraph, bundle; sorted=sorted, use_bins=true
        )
        lbCost = get_path_cost(lbPath, TTGraph.costMatrix)
        # Selecting the best one
        if bestCost > lbCost
            counters["LB Better"] += 1
            pathCost < costRemoved && (improvCharac["LB"] += costRemoved - pathCost)
            bestCost, bestPath = lbCost, lbPath
            update_counters!(
                lbCounters, recomputedLB, giantBetter, giantDiff; lowerBound=true
            )
        else
            update_counters!(greedyCounters, recomputedG, binUsedBetter, binUsedDiff)
            pathCost < costRemoved && (improvCharac["Greedy"] += costRemoved - pathCost)
        end

        # Updating path if it improves the cost
        if pathCost < costRemoved
            costImprov += costRemoved - pathCost
            improvCharac["Total"] += 1
            length(paths[1]) == 2 && improvCharac["On Direct"] += 1
            improvCharac["Mean Orders"] += length(bundle.orders)
            improvCharac["Mean Commo"] += sum(o -> length(o.content), bundle.orders)
            improvCharac["Mean Volume"] += sum(o -> o.volume, bundle.orders)
            update_solution!(solution, instance, bundles, [bestPath]; sorted=true)
        else
            counters["No Improv"] += 1
            paths[1] == bestPath && counters["Same Path"] += 1
            update_solution!(
                solution, instance, bundles, paths; remove=true, skipRefill=true
            )
            revert_bins!(sol, previousBins)
        end
    end
    println("\nCost improvement : $costImprov")
    greedyCounters["Bin Used Mean Diff"] =
        greedyCounters["Bin Used Diff"] / greedyCounters["Bin Used Better"]
    binNotUsedBetter = greedyCounters["Recomputed"] - greedyCounters["Bin Used Better"]
    greedyCounters["Bin Not Used Mean Diff"] =
        greedyCounters["Bin Not Used Diff"] / binNotUsedBetter
    println("Geedy counters : \n$(print_counters(greedyCounters))")
    lbCounters["Giant Better Mean Diff"] =
        lbCounters["Giant Better Diff"] / lbCounters["Giant Better"]
    binNotUsedBetter = lbCounters["Recomputed"] - lbCounters["Giant Better"]
    lbCounters["Giant Worse Mean Diff"] =
        lbCounters["giant Not Used Diff"] / binNotUsedBetter
    println("Lower bound counters : \n$(print_counters(lbCounters))")
    println("Improvement characteristic : \n$(print_counters(lbCounters))")
    println()
    return costImprov
end

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
            src != dst && counters["Filtered"] += 1
            continue
        end
        twoNodeBundles = get_bundles_to_update(solution, src, dst)
        if length(twoNodeBundles) == 0
            counters["No Bundles"] += 1
            continue
        end
        twoNodePaths = get_paths_to_update(solution, twoNodeBundles, src, dst)
        # Saving previous solution state 
        previousBins, costRemoved = save_and_remove_bundle!(
            solution, TSGraph, TTGraph, bundles, twoNodePaths; current_cost=current_cost
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
            update_cost_matrix!(
                solution, TTGraph, TSGraph, bundle; sorted=sorted, use_bins=true
            )
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
            return revert_bins!(solution, previousBins)
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