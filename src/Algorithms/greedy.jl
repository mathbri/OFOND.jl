# Sort bundle by maximum packaging size

# For every bundle :
#     Extract a bundle specific travel time subgraph from the complete one 
#     Compute travel time arc cost :
#         For every arc in the bundle subgraph :
#              If the arc has a linear cost structure : multiply the linear cost with the sumed orders volume
#              If the arc has a bin-packing cost structure : 
#                  For each order and corresponding timed arc : 
#                      If the arc is empty : multiply arc cost with pre-computed ffd packing
#                      Otherwise : compute explicitly with a bin-packing function the added number of trucks and multiply with arc truck cost
#         Add regularization cost on the arcs
#     Compute the shortest path from supplier (with stepsToDelivery = maxDeliveryTime) to customer (with stepsToDelivery = 0)
#     If path not elementary :
#         divide opening cot of trucks by 2
#     If path not elementary :
#         do not take into account current loading
#     Store bundle path in Solution object 
#     Update time space graph :
#         For all arc in the path, update timed arcs loading with the corresponding bundle order content

# TODO : add heuristic like linear unit cost for a_star and see if the results are better
# Using this heuristic to prune nodes already encountered in the search space would be a good idea
# a star implementation relatively easy so can be re-implemented

# TODO : add regul cost ? carbon cost already linear in distance and volume
# Discuss both with axel ? Maybe just testing it on the world instance

# TODO : if update cost matrix is really expensive, do it once with every option and store all option results in different objects

# Compute path and cost for the greedy insertion of a bundle, not handling path admissibility
function greedy_path(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
    sorted::Bool=false,
    use_bins::Bool=true,
    opening_factor::Float64=1.0,
    current_cost::Bool=false,
)
    update_cost_matrix!(
        solution,
        TTGraph,
        TSGraph,
        bundle;
        sorted=sorted,
        use_bins=use_bins,
        opening_factor=opening_factor,
        current_cost=current_cost,
    )
    dijkstraState = dijkstra_shortest_paths(TTGraph.graph, src, TTGraph.costMatrix)
    shortestPath = enumerate_paths(dijkstraState, dst)
    removedCost = remove_shortcuts!(shortestPath, TTGraph)
    pathCost = dijkstraState.dists[dst]
    return shortestPath, pathCost - removedCost
end

# Compute the path and cost for the greedy insertion of a bundle, handling path admissibility
function greedy_insertion(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
    sorted::Bool=false,
    current_cost::Bool=false,
)
    shortestPath, pathCost = greedy_path(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        src,
        dst;
        sorted=sorted,
        use_bins=true,
        current_cost=current_cost,
    )
    # If the path is not admissible, re-computing it
    if !is_path_admissible(TTGraph, shortestPath)
        # TODO : store this path cost matrix in travel time graph if the recomputation is needed numerous times 
        # First trying to halve cost for the path computation
        costMatrix = deepcopy(TTGraph.costMatrix)
        shortestPath, pathCost = greedy_path(
            solution,
            TTGraph,
            TSGraph,
            bundle,
            src,
            dst;
            sorted=sorted,
            use_bins=true,
            opening_factor=0.5,
            current_cost=current_cost,
        )
        pathCost = path_cost(shortestPath, costMatrix)
        if !is_path_admissible(TTGraph, shortestPath)
            # Then not taking into account the current solution
            # If this happens, we want to be sure to have an admissible path
            shortestPath, pathCost = greedy_path(
                solution,
                TTGraph,
                TSGraph,
                bundle,
                src,
                dst;
                sorted=sorted,
                use_bins=false,
                current_cost=false,
            )
            pathCost = path_cost(shortestPath, costMatrix)
        end
    end
    return shortestPath, pathCost
end

function greedy!(solution::Solution, instance::Instance)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Sorting commodities in orders and bundles between them
    sort_order_content!(instance)
    sortedBundleIdxs = sortperm(instance.bundles; by=bun -> bun.maxPackSize, rev=true)
    # Computing the greedy delivery possible for each bundle
    totalCost = 0.0
    for bundleIdx in sortedBundleIdxs
        bundle = instance.bundles[bundleIdx]
        # Retrieving bundle start and end nodes
        suppNode = TTGraph.bundleSrc[bundleIdx]
        custNode = TTGraph.bundleDst[bundleIdx]
        # Computing shortest path
        shortestPath, pathCost = greedy_insertion(
            solution, TTGraph, TSGraph, bundle, suppNode, custNode; sorted=true
        )
        # Adding to solution
        updateCost = update_solution!(
            solution, instance, [bundle], [shortestPath]; sorted=true
        )
        # verification (correcting path cost from bias in cost computation)
        # if !(pathCost ≈ updateCost)
        #     println("Path cost $pathCost")
        #     println("Corrected cost $(pathCost - (length(shortestPath) - 1) * EPS)")
        #     println("TTGraph cost matrix : $(TTGraph.costMatrix)")
        # end
        # pathCost -= (length(shortestPath) - 1) * EPS
        # @assert pathCost ≈ updateCost "Path cost ($pathCost) and Update cost ($updateCost) don't match, check the error \n bundle : $bundle \n shortestPath : $shortestPath \n bundleIdx : $bundleIdx"
        @assert isapprox(pathCost, updateCost; atol=10 * EPS) "Path cost ($pathCost) and Update cost ($updateCost) don't match, check the error \n bundle : $bundle \n shortestPath : $shortestPath \n bundleIdx : $bundleIdx"
        totalCost += updateCost
    end
    return totalCost
end