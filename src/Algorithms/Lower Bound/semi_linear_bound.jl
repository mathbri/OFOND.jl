# Build network graph from instance 
    # Build travel time graph from network graph

    # For every bundle :
    #     Extract a bundle specific travel time subgraph from the complete one 
    #     Compute travel time arc cost :
    #         For every arc in the bundle subgraph :
    #              If the arc has a linear cost structure : multiply the linear cost with the sumed orders volume
    #              If the arc has a bin-packing cost structure : linearize arc cost and multiply with sumed order volume
    #     Compute the shortest path from supplier (with stepsToDelivery = maxDeliveryTime) to customer (with stepsToDelivery = 0)
    #     Add path cost to the lower bound value
    #     Store bundle path in Solution object 
    #     Update time space graph :
    #         For all arc in the path, update timed arcs loading with the corresponding bundle order content 

    # Construct and return solution object 

# Compute the update directly on the bins 
function update_lb_cost_matrix!(travelTimeUtils::TravelTimeUtils, travelTimeGraph::TravelTimeGraph, updateNodes::Vector{Int}, bundle::Bundle, bundleDst::Int, bundleUtil::BundleUtils)
    # Iterating through all update nodes and their outneighbors
    for src in updateNodes
        for dst in outneighbors(travelTimeGraph, src)
            dstData = travelTimeGraph.networkNodes[dst]
            arcData = travelTimeGraph.networkArcs[src, dst]
            # If it is a shortcut leg, cost alredy set to EPS
            arcData.type == :shortcut && continue
            # If the destination is not the right plant, not updating cost
            (arcData.type == :shortcut && dst != bundleDst) && continue
            # Adding cost for each order in the bundle
            arcBundleCost = EPS
            for (idxO, order) in enumerate(bundle.orders)
                orderUtil = bundleUtil.orderUtils[idxO]
                # Node volume cost 
                arcBundleCost += dstData.volumeCost * orderUtil.volume
                # Commodity cost 
                arcBundleCost += arcData.distance * orderUtil.leadTimeCost
                # Transport cost 
                if arcData.type == :direct
                    arcBundleCost += orderUtil.giantUnits * (arcData.unitCost + arcData.carbonCost)
                else
                    arcBundleCost += (orderUtil.volume / arcData.capacity) * (arcData.unitCost + arcData.carbonCost)
                end
            end
            travelTimeUtils.costMatrix[src, dst] = arcBundleCost
        end
    end
end

function semi_linear_bound_heuristic(instance::Instance)
    startTime = time()
    
    # Build travel time and time space graphs from instance
    travelTimeGraph, travelTimeUtils = build_travel_time_and_utils(instance.networkGraph, instance.bundles)
    timeSpaceGraph, timeSpaceUtils = build_time_space_and_utils(instance.networkGraph, instance.timeHorizon)
    bundlePaths = Vector{Vector{Int}}()
    # Computing bundles, orders, and commodities utils
    bundleUtils = [BundleUtils(bundle, first_fit_decreasing, LAND_CAPACITY) for bundle in instance.bundles]
    
    # Saving pre-solve time
    preSolveTime = round((time() - startTime) * 1000) / 1000
    println("Pre-solve time : $preSolveTime s")

    lowerBound = 0.
    # Computing the greedy delivery possible for each bundle
    for bundleIdx in sortedBundleIdxs
        bundle = instance.bundles[bundleIdx]
        bundleUtil = bundleUtils[bundleIdx]
        # Retrieving bundle start and end nodes
        suppNode = travelTimeUtils.bundleStartNodes[bundleIdx]
        custNode = travelTimeUtils.bundleEndNodes[bundleIdx]
        # Updating cost matrix 
        bundleUpdateNodes = get_bundle_update_nodes(travelTimeUtils, travelTimeGraph, bundleIdx)
        update_lb_cost_matrix!(travelTimeUtils, travelTimeGraph, bundleUpdateNodes, bundle, travelTimeUtils.bundleEndNodes[bundleIdx], bundleUtil)
        # Computing shortest path
        dijkstraState = dijkstra_shortest_paths(travelTimeGraph, suppNode, travelTimeUtils.costMatrix)
        shortestPath = enumerate_paths(dijkstraState, custNode)
        pathCost = dijkstraState.dists[custNode]
        lowerBound += pathCost
        remove_shotcuts!(shortestPath, travelTimeGraph)
        # Adding shortest path to all bundle paths
        push!(bundlePaths, get_path_nodes(shortestPath))
        # Updating the loads for each order of the bundle
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

# You can also add a milp phase here only for the shared network if it is not too big 

function semi_linear_bound()
    # Do the same but don't compute the corresponding solution
end