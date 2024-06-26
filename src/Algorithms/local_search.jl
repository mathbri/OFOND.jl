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
# Another option for insertion is to make a first round of insertion without constraint and if there is arcs that does not satisfy, take all bundles of it, forbid arc for every one and recompute insertion and repaeat until constraint are good

# Other question : 
# Instead of computing greedy and lower boud paths, would it be better to divide it into two different operators ?
# Like reintroduce all bundles with greedy path and then reintroduce all bundles with lower bound paths ?

# Improving all bin packings if possible
# The idea is to put skip linear to false just before returning the solution to get a more compact solution but it does not affect the cost
function bin_packing_improvement!(
    solution::Solution, instance::Instance; sorted::Bool=false, skipLinear::Bool=true
)
    costImprov = 0.0
    for arc in edges(instance.timeSpaceGraph.graph)
        arcBins = solution.bins[src(arc), dst(arc)]
        arcData = instance.timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        # If no improvement possible
        is_bin_candidate(arcBins, arcData; skipLinear=skipLinear) || continue
        # Gathering all commodities
        allCommodities = get_all_commodities(arcBins)
        # Computing new bins
        newBins = compute_new_bins(arcData, allCommodities; sorted=sorted)
        # If the number of bins did not change, skipping next
        length(newBins) >= length(arcBins) && continue
        # Updating bins
        solution.bins[src(arc), dst(arc)] = newBins
        # Computing cost improvement (unless linear arc)
        arcData.isLinear && continue
        costImprov += arcData.unitCost * (length(arcBins) - length(newBins))
    end
    return costImprov
end

# All arcs are independant when computing bin-packing so can be parrallelized
function parrallel_bin_packing_improvement!(
    solution::Solution, instance::Instance; sorted::Bool=false, skipLinear::Bool=true
)
    # TODO : parrallelize here with native @threads
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
    bundles, oldPaths = [bundle], [solution.bundlePaths[bundle.idx]]
    # Saving previous solution state 
    oldBins, costRemoved = save_and_remove_bundle!(
        solution, instance, bundles, oldPaths; current_cost=current_cost
    )
    # If the cost removed only amouts to the linear part of the cost, no chance of improving, at best the same cost
    pathsLinearCost = bundle_path_linear_cost(bundle, oldPaths[1], TTGraph)
    if costRemoved + pathsLinearCost >= -EPS
        update_solution!(solution, instance, bundles, oldPaths; skipRefill=true)
        # Reverting bins to the previous state
        revert_bins!(solution, oldBins)
        return 0.0
    end
    # Inserting it back
    suppNode = TTGraph.bundleSrc[bundle.idx]
    custNode = TTGraph.bundleDst[bundle.idx]
    newPath, pathCost = greedy_insertion(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        suppNode,
        custNode;
        sorted=sorted,
        current_cost=current_cost,
    )
    # Updating path if it improves the cost (accounting for EPS cost on arcs)
    if pathCost + costRemoved < -1e-3
        # Adding to solution
        updateCost = update_solution!(solution, instance, bundles, [newPath]; sorted=true)
        # verification
        @assert isapprox(pathCost, updateCost; atol=10 * EPS) "Path cost ($pathCost) and Update cost ($updateCost) don't match \n bundle : $bundle \n shortestPath : $shortestPath \n bundleIdx : $bundleIdx"
        return pathCost + costRemoved
    else
        update_solution!(solution, instance, bundles, oldPaths; skipRefill=true)
        revert_bins!(solution, oldBins)
        return 0.0
    end
end

# TODO : do Oscar's trick for memory efficient computation
# Define solution2 (or lbSol) outside of the function, modify them both in the function 
# and permute the return to choose the best, the other being the one not needed 
# ie return (sol, sol2) or (sol2, sol)
# is it really applicable here as we have to start from the same solution ?
# not exactly as we have to make them both equal at the end of the neighborhood function 
# but just need to create this function that make them equal and we can avoid allocating memory for all the old paths and bins
# this trick could be used also for the other neighborhoods

# Remove and insert back all bundles flowing from src to dst 
function two_node_incremental!(
    solution::Solution,
    instance::Instance,
    src::Int,
    dst::Int;
    sorted::Bool=false,
    current_cost::Bool=false,
)
    TTGraph = instance.travelTimeGraph
    twoNodeBundles = get_bundles_to_update(solution, src, dst)
    # If there is no bundles concerned, returning
    length(twoNodeBundles) == 0 && return nothing
    oldPaths = get_paths_to_update(solution, twoNodeBundles, src, dst)
    # Saving previous solution state 
    oldBins, costRemoved = save_and_remove_bundle!(
        solution, instance, twoNodeBundles, oldPaths; current_cost=current_cost
    )
    # If the cost removed only amouts to the linear part of the cost, no chance of improving, at best the same cost
    pathsLinearCost = sum(
        bundle_path_linear_cost(bundle, path, TTGraph) for
        (bundle, path) in zip(twoNodeBundles, oldPaths)
    )
    if costRemoved + pathsLinearCost >= -EPS
        update_solution!(solution, instance, bundles, oldPaths; skipRefill=true)
        revert_bins!(solution, oldBins)
        return 0.0
    end
    # Inserting it back
    greedyAddedCost, lbAddedCost, lbSol = 0.0, 0.0, deepcopy(solution)
    sortedBundleIdxs = sortperm(twoNodeBundles; by=bun -> bun.maxPackSize, rev=true)
    for bundleIdx in sortedBundleIdxs
        bundle = twoNodeBundles[bundleIdx]
        greedyPath, lowerBoundPath = both_insertion(
            solution, instance, bundle, src, dst; sorted=sorted, current_cost=current_cost
        )
        # Adding to solutions
        greedyAddedCost += update_solution!(
            solution, instance, [bundle], [greedyPath]; sorted=sorted
        )
        lbAddedCost += update_solution!(
            lbSol, instance, [bundle], [lowerBoundPath]; sorted=sorted
        )
    end
    # Solution already updated so if it didn't improve, reverting to old state
    if min(greedyAddedCost, lbAddedCost) + costRemoved > -1e-3
        # solution is already updated so needs to remove bundle on nodes again
        update_solution!(solution, instance, twoNodeBundles, oldPaths; remove=true)
        update_solution!(solution, instance, twoNodeBundles, oldPaths; skipRefill=true)
        revert_bins!(solution, oldBins)
        return 0.0
    else
        # Choosing the best update (greedy by default)
        if greedyAddedCost > lbAddedCost
            change_solution_to_other!(
                solution, lbSol, instance, twoNodeBundles; sorted=sorted
            )
            return lbAddedCost + costRemoved
        else
            return greedyAddedCost + costRemoved
        end
    end
end

function local_search!(solution::Solution, instance::Instance)
    # Combine the three small neighborhoods
    TTGraph = instance.travelTimeGraph
    sort_order_content!(instance)
    # First, bundle reintroduction to change whole paths
    bundleIdxs = randperm(length(instance.bundles))
    for bundleIdx in bundleIdxs
        bundle = instance.bundles[bundleIdx]
        bundle_reintroduction!(solution, instance, bundle; sorted=true)
    end
    # Second, two node incremental to optimize shared network
    plantNodes = findall(x -> x.type == :plant, TTGraph.networkNodes)
    two_node_nodes = vcat(TTGraph.commonNodes, plantNodes)
    for src in two_node_nodes, dst in two_node_nodes
        are_nodes_candidate(TTGraph, src, dst) || continue
        two_node_incremental!(solution, instance, src, dst; sorted=true)
    end
    # Finally, bin packing improvement to optimize packings
    return bin_packing_improvement!(solution, instance; sorted=true)
end