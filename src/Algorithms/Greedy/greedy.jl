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

function greedy_heuristic(instance::Instance)
    startTime = time()
    
    # Build travel time and time space graphs from instance
    travelTimeGraph, travelTimeUtils = build_travel_time_and_utils(instance.networkGraph, instance.bundles)
    timeSpaceGraph, timeSpaceUtils = build_time_space_and_utils(instance.networkGraph, instance.timeHorizon)
    bundlePaths = Vector{Vector{Int}}()
    # Computing bundles, orders, and commodities utils
    bundleUtils = [BundleUtils(bundle, first_fit_decreasing, LAND_CAPACITY) for bundle in instance.bundles]
    # Sorting commodities in orders and bundles between them
    sort_order_content!(instance)
    sortedBundleIdxs = sortperm(bundleUtils, by=bun->bun.maxPackSize, rev=true)
    
    # Saving pre-solve time
    preSolveTime = round((time() - startTime) * 1000) / 1000
    println("Pre-solve time : $preSolveTime s")
    
    # Computing the greedy delivery possible for each bundle
    for bundleIdx in sortedBundleIdxs
        bundle = instance.bundles[bundleIdx]
        bundleUtil = bundleUtils[bundleIdx]
        # Retrieving bundle start and end nodes
        suppNode = travelTimeUtils.bundleStartNodes[bundleIdx]
        custNode = travelTimeUtils.bundleEndNodes[bundleIdx]
        # Updating cost matrix 
        bundleUpdateNodes = get_bundle_update_nodes(travelTimeUtils, travelTimeGraph, bundleIdx)
        update_cost_matrix!(travelTimeUtils, travelTimeGraph, bundleUpdateNodes, bundle, travelTimeUtils.bundleEndNodes[bundleIdx], bundleUtil, timeSpaceUtils)
        # Computing shortest path
        shortestPath = a_star(travelTimeGraph, suppNode, custNode, travelTimeUtils.costMatrix)
        # TODO : If path not elementary, dividing opening cot of trucks by 2
        # if !is_path_elementary(shortestPath)
        #     update_cost_matrix!(travelTimeUtils, travelTimeGraph, bundle, timeSpaceUtils)
        #     shortestPath = a_star(travelTimeGraph, suppNode, custNode, travelTimeUtils.costMatrix)
        #     # If path not elementary, not taking into account current solution
        #     if !is_path_elementary(shortestPath)
        #         update_cost_matrix!(travelTimeUtils, travelTimeGraph, bundle, timeSpaceUtils)
        #         shortestPath = a_star(travelTimeGraph, suppNode, custNode, travelTimeUtils.costMatrix)
        #     end
        # end
        # Adding shortest path to all bundle paths
        push!(bundlePaths, get_path_nodes(shortestPath))
        # Updating the loads for each order of the bundle
        for order in bundle.orders
            update_loads!(timeSpaceUtils, timeSpaceGraph, travelTimeGraph, shortestPath, order)
        end
    end

    # Computing the actual bin packing 
    # Done here because its cheaper to compute tentative packings on vectors of int than vectors of bins
    for bundleIdx in sortedBundleIdxs
        bundle = instance.bundles[bundleIdx]
        for order in bundle.orders
            update_bins!(timeSpaceGraph, travelTimeGraph, shortestPath, order)
        end
    end

    # Saving solve time
    solveTime = round((time() - preSolveTime) * 1000) / 1000
    println("solve time : $solveTime s")
    solution = Solution(travelTimeGraph, bundlePaths, timeSpaceGraph)
    println("Feasible : $(is_feasible(instance, solution))")
    println("Total Cost : $(compute_cost(solution))")

    return solution 
end