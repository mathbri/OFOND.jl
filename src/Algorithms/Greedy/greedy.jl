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

function greedy_insertion(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    suppNode::Int,
    custNode::Int,
)
    dijkstraState = dijkstra_shortest_paths(TTGraph, suppNode, travelTimeUtils.costMatrix)
    shortestPath = enumerate_paths(dijkstraState, custNode)

    # If recomputation needed ?
    if is_new_path_needed(TTGraph, shortestPath)
        update_cost_matrix!(
            solution,
            TTGraph,
            TSGraph,
            bundle;
            sorted=true,
            use_bins=true,
            opening_factor=0.5,
        )
        dijkstraState = dijkstra_shortest_paths(
            TTGraph, suppNode, travelTimeUtils.costMatrix
        )
        shortestPath = enumerate_paths(dijkstraState, custNode)

        if is_new_path_needed(TTGraph, shortestPath)
            update_cost_matrix!(
                solution, TTGraph, TSGraph, bundle; sorted=true, use_bins=false
            )
            dijkstraState = dijkstra_shortest_paths(
                TTGraph, suppNode, travelTimeUtils.costMatrix
            )
            shortestPath = enumerate_paths(dijkstraState, custNode)
        end
    end
    pathCost = dijkstraState.dists[custNode]
    return shortestPath, pathCost
end

function greedy!(solution::Solution, instance::Instance)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Sorting commodities in orders and bundles between them
    sort_order_content!(instance)
    sortedBundleIdxs = sortperm(bundles; by=bun -> bun.maxPackSize, rev=true)
    # Computing the greedy delivery possible for each bundle
    for bundleIdx in sortedBundleIdxs
        bundle = instance.bundles[bundleIdx]
        update_cost_matrix!(solution, TTGraph, TSGraph, bundle; sorted=true, use_bins=true)

        # Retrieving bundle start and end nodes
        suppNode = TTGraph.bundleStartNodes[bundleIdx]
        custNode = TTGraph.bundleEndNodes[bundleIdx]
        # Computing shortest path
        shortestPath, pathCost = greedy_insertion(
            solution, TTGraph, TSGraph, bundle, suppNode, custNode
        )

        # Adding path to solution
        remove_shotcuts!(shortestPath, travelTimeGraph)
        add_path!(solution, bundle, shortestPath)
        # Updating the bins for each order of the bundle
        for order in bundle.orders
            update_bins!(solution, TSGraph, TTGraph, shortestPath, order; sorted=true)
        end
    end
end