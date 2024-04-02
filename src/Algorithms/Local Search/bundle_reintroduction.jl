# Build network graph from instance 
    # Build travel time graph from network graph
    # Copy Solution object (to have a best solution and a current solution that you modify on the fly)

    # At each iteration :
    #     For every bundle (or subset of bundles if specified) :
    #         Remove the bundle from the current solution 
    #         Store previous state of all arcs modified by this removal
    #         Insert it back greedily
    #     If the cost is better than the best one encountered so far :
    #         Store the new best solution inplace of the old one 
    #     If no increase :
    #         divide opening cot of trucks by 2
    #     If no increase :
    #         do not take into account current loading
    #     Otherwise, revert the current solution to its previous state

    # Return the best solution

function bundle_reintroduction_local_search(instance::Instance, solution::Solution)
    startTime = time()
    
    # Build travel time and time space graphs from instance
    travelTimeGraph, travelTimeUtils = build_travel_time_and_utils(instance.networkGraph, instance.bundles)
    travelTimeGraph = deepcopy(solution.travelTimeGraph)
    timeSpaceGraph, timeSpaceUtils = build_time_space_and_utils(instance.networkGraph, instance.timeHorizon)
    timeSpaceGraph = deepcopy(solution.timeSpaceGraph)
    bundlePaths = deepcopy(solution.bundlePaths)
    # Computing bundles, orders, and commodities utils
    bundleUtils = [BundleUtils(bundle, first_fit_decreasing, LAND_CAPACITY) for bundle in instance.bundles]
    # Copy Solution object (to have a best solution and a current solution that you modify on the fly)

    # Computing the greedy delivery possible for each bundle
    for bundleIdx in shuffle(1:length(instance.bundles))
        bundle = instance.bundles[bundleIdx]
        bundleUtil = bundleUtils[bundleIdx]
        # Reintroducing the bundle
        newPath = bundle_reintroduction!(timeSpaceGraph, travelTimeGraph, bundle, bundleIdx, bundleUtil, bundlePaths[bundleIdx], timeSpaceUtils, travelTimeUtils)
        # Storing new path
        bundlePaths[bundleIdx] = newPath
    end

    # Saving solve time
    solveTime = round((time() - preSolveTime) * 1000) / 1000
    println("solve time : $solveTime s")
    solution = Solution(travelTimeGraph, bundlePaths, timeSpaceGraph)
    println("Feasible : $(is_feasible(instance, solution))")
    println("Total Cost : $(compute_cost(solution))")

    return solution 
end

# Turn this local search into an operator by doing it just for one bundle

function bundle_reintroduction!(timeSpaceGraph::TimeSpaceGraph, travelTimeGraph::TravelTimeGraph, bundle::Bundle, bundleIdx::Int, bundleUtil::BundleUtil, path::Vector{Int}, timeSpaceUtils::TimeSpaceUtils, travelTimeUtils::TravelTimeUtils)
    # Save previous bins 
    previousBins, previousCost = save_previous_bins(timeSpaceGraph, travelTimeGraph, bundle, path)
    # Remove the bundle from the current solution 
    remove_bundle!(timeSpaceGraph, travelTimeGraph, bundle, path)
    # Adpat the bins to this removal
    costAfterRefill = refill_bins!(timeSpaceGraph, travelTimeGraph, bundle, path)
    # If the cost removed is negative or null, no chance of improving 
    if previousCost - costAfterRefill <= 0
        # Reverting bins to the previous state
        revert_bins!(timeSpaceGraph, travelTimeGraph, bundle, path, previousBins)
        # Returning the old path
        return path
    end
    # Insert it back greedily
    # Retrieving bundle start and end nodes
    suppNode = travelTimeUtils.bundleStartNodes[bundleIdx]
    custNode = travelTimeUtils.bundleEndNodes[bundleIdx]
    # Updating cost matrix 
    bundleUpdateNodes = get_bundle_update_nodes(travelTimeUtils, travelTimeGraph, bundleIdx)
    update_cost_matrix!(travelTimeUtils, travelTimeGraph, bundleUpdateNodes, bundle, travelTimeUtils.bundleEndNodes[bundleIdx], bundleUtil, timeSpaceUtils)
    # Computing shortest path
    dijkstraState = dijkstra_shortest_paths(travelTimeGraph, suppNode, travelTimeUtils.costMatrix)
    shortestPath = enumerate_paths(dijkstraState, custNode)
    pathCost = dijkstraState.dists[custNode]
    # Returning new path if it improves the cost
    if pathCost < (previousCost - costAfterRefill)
        remove_shotcuts!(shortestPath, travelTimeGraph)
        return shortestPath
    else
        revert_bins!(timeSpaceGraph, travelTimeGraph, bundle, path, previousBins)
        return path 
    end
end