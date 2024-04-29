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

function lower_bound_path(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
    use_bins::Bool,
    current_cost::Bool,
    giant::Bool,
)
    update_lb_cost_matrix!(
        solution,
        TTGraph,
        TSGraph,
        bundle;
        use_bins=use_bins,
        current_cost=current_cost,
        giant=giant,
    )
    dijkstraState = dijkstra_shortest_paths(TTGraph, src, TTGraph.costMatrix)
    shortestPath = enumerate_paths(dijkstraState, dst)
    pathCost = dijkstraState.dists[dst]
    return shortestPath, pathCost
end

function lower_bound_insertion(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
    use_bins::Bool=false,
    current_cost::Bool=false,
    giant::Bool=false,
)
    shortestPath, pathCost = lower_bound_path(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        src,
        dst;
        use_bins=use_bins,
        current_cost=current_cost,
        giant=giant,
    )
    # If the path is not admissible, re-computing it
    if use_bins && !is_path_admissible(TTGraph, shortestPath)
        shortestPath, pathCost = lower_bound_path(
            solution,
            TTGraph,
            TSGraph,
            bundle,
            src,
            dst;
            use_bins=false,
            current_cost=current_cost,
            giant=giant,
        )
    end
    return shortestPath, pathCost
end

function lower_bound!(solution::Solution, instance::Instance)
    lowerBound = 0.0
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Sorting commodities in orders and bundles between them
    sort_order_content!(instance)
    # Computing the lower bound delivery for each bundle
    for bundle in instance.bundles
        # Retrieving bundle start and end nodes
        suppNode = TTGraph.bundleStartNodes[bundle.idx]
        custNode = TTGraph.bundleEndNodes[bundle.idx]
        # Computing shortest path
        shortestPath, pathCost = lower_bound_insertion(
            solution, TTGraph, TSGraph, bundle, suppNode, custNode;
        )
        lowerBound += pathCost
        # Adding path to solution
        remove_shotcuts!(shortestPath, travelTimeGraph)
        add_path!(solution, bundle, shortestPath)
        # Updating the bins for each order of the bundle
        for order in bundle.orders
            update_bins!(solution, TSGraph, TTGraph, shortestPath, order; sorted=true)
        end
    end
    return lowerBound
end

# TODO : use this heuristic as a filtering operation on the instance ?
# I run the lower bound heuristic : it splits my instance between directs and non-directs 
# Because the cost is lower bound, the directs are sure to be one ?
# Than I can just consider the non-directs for the LNS
