# Algorithms analysis functions

# Mostly used to identify / quantify the most promosing operations in the different algorithms
# To be used with @time or @profile or @profile_alloc

function lower_bound_analysis() end

function greedy_analysis() end

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
        bestCost, bestPath = greedy_insertion(
            solution,
            TTGraph,
            TSGraph,
            bundle,
            suppNode,
            custNode;
            sorted=true,
            current_cost=false,
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
        if bestCost > lbCost
            lbBetterCount += 1
            pathCost < costRemoved && (lbImprov += costRemoved - pathCost)
            bestCost, bestPath = lbCost, lbPath
        else
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
    println()
    return costImprov
end

function two_node_incremental_analysis!() end

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