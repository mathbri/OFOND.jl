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

# Other question : 
# Instead of computing greedy and lower boud paths, would it be better to divide it into two different operators ?
# Like reintroduce ann bundles with greedy path and then reintroduce all bundles with lower bound paths ?

# Improving all bin packings if possible
# The idea is to put skip linear to false just before returning the solution to get a more compact solution but it does not affect the cost
function bin_packing_improvement!(
    solution::Solution, instance::Instance; sorted::Bool=false, skipLinear::Bool=true
)
    costImprov = 0.0
    for arc in edges(instance.timeSpaceGraph)
        arcBins = solution.bins[src(arc), dst(arc)]
        arcData = instance.timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        # If no improvement possible
        is_bin_candidate(arcBins, arcData; skipLinear=skipLinear) || continue
        # Gathering all commodities
        allCommodities = reduce(vcat, arcBins)
        # Computing new bins
        newBins = compute_new_bins(arcData, allCommodities; sorted=sorted)
        # If the number of bins did not change, skipping next
        length(newBins) >= length(arcBins) && continue
        # Computing cost improvement
        costImprov +=
            (arcData.unitCost + arcData.carbonCost) * (length(arcBins) - length(newBins))
        # Updating bins
        solution.bins[src(arc), dst(arc)] = newBins
    end
    return costImprov
end

# Removing and inserting back the bundle in the solution.
# If the operation did not lead to a cost improvement, reverting back to the former state of the solution.
function bundle_reintroduction!(
    solution::Solution,
    instance::Instance,
    bundle::Bundle;
    sorted::Bool=false,
    current_cost::Bool=false,
)
    # compute greedy insertion and lower bound insertion and take the best one ?
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    bundles, paths = [bundle], [solution.bundlePaths[bundle.idx]]
    # Saving previous solution state 
    previousBins, costRemoved = save_and_remove_bundle!(
        solution, TSGraph, TTGraph, bundles, paths; current_cost=current_cost
    )
    # If the cost removed is negative or null, no chance of improving 
    if costRemoved <= 0
        # Reverting bins to the previous state
        return revert_bins!(solution, previousBins)
    end
    # Inserting it back
    suppNode = TTGraph.bundleStartNodes[bundle.idx]
    custNode = TTGraph.bundleEndNodes[bundle.idx]
    bestCost, bestPath = best_reinsertion(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        suppNode,
        custNode;
        sorted=sorted,
        current_cost=current_cost,
    )
    # Updating path if it improves the cost
    if pathCost < costRemoved
        # Adding to solution
        updateCost = update_solution!(solution, instance, [bundle], [bestPath]; sorted=true)
        # verification
        @assert isapprox(bestCost, updateCost) "Path cost and Update cost don't match, check the error"
        return nothing
    else
        return revert_bins!(solution, previousBins)
    end
end

# Remove and insert back all bundles flowing from src to dst 
function two_node_incremental!(
    solution::Solution,
    instance::Instance,
    src::Int,
    dst::Int;
    sorted::Bool=false,
    current_cost::Bool=false,
)
    twoNodeBundles = get_bundles_to_update(solution, src, dst)
    twoNodePaths = get_paths_to_update(solution, twoNodeBundles, src, dst)
    # Saving previous solution state 
    previousBins, costRemoved = save_and_remove_bundle!(
        solution, TSGraph, TTGraph, bundles, twoNodePaths; current_cost=current_cost
    )
    # Inserting it back
    addedCost = 0.0
    for bundle in twoNodeBundles
        bestCost, bestPath = best_reinsertion(
            solution,
            TTGraph,
            TSGraph,
            bundle,
            src,
            dst;
            sorted=sorted,
            current_cost=current_cost,
        )
        addedCost += bestCost
        # Adding to solution
        updateCost = update_solution!(solution, instance, [bundle], [bestPath]; sorted=true)
        # verification
        @assert isapprox(bestCost, updateCost) "Path cost and Update cost don't match, check the error"
    end
    # Solution already updated so if it didn't improve, reverting to old state
    if addedCost < costRemoved
        update_solution!(solution, instance, twoNodeBundles, twoNodePaths; remove=true)
        update_solution!(solution, instance, twoNodeBundles, twoNodePaths; skipRefill=true)
        return revert_bins!(solution, previousBins)
    end
end

function local_search!(solution::Solution, instance::Instance)
    # Combine the three small neighborhoods
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    sort_order_content!(instance)
    # First, bundle reintroduction to change whole paths
    for bundle in instance.bundles
        bundle_reintroduction!(solution, instance, bundle; sorted=true)
    end
    # Second, two node incremental to optimize shared network
    for src in TTGraph.commonNodes, dst in TTGraph.commonNodes
        src == dst && continue
        two_node_incremental!(solution, instance, src, dst; sorted=true)
    end
    # Finally, bin packing improvement to optimize packings
    return bin_packing_improvement!(solution, instance; sorted=true)
end