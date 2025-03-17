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
    use_bins::Bool=false,
    current_cost::Bool=false,
    giant::Bool=false,
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
    dijkstraState = dijkstra_shortest_paths(TTGraph.graph, src, TTGraph.costMatrix)
    shortestPath = enumerate_paths(dijkstraState, dst)
    removedCost = remove_shortcuts!(shortestPath, TTGraph)
    pathCost = dijkstraState.dists[dst]
    return shortestPath, pathCost - removedCost
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
    pureLowerBound = !use_bins && !current_cost && !giant
    if !pureLowerBound && !is_path_admissible(TTGraph, shortestPath)
        shortestPath, pathCost = lower_bound_path(
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
    end
    return shortestPath, pathCost
end

function lower_bound!(solution::Solution, instance::Instance)
    lowerBound = 0.0
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Sorting commodities in orders and bundles between them
    sort_order_content!(instance)
    # Computing the lower bound delivery for each bundle
    println("Lower Bound insertion progress : ")
    percentIdx = ceil(Int, length(instance.bundles) / 100)
    for (i, bundle) in enumerate(instance.bundles)
        # Retrieving bundle start and end nodes
        suppNode = TTGraph.bundleSrc[bundle.idx]
        custNode = TTGraph.bundleDst[bundle.idx]
        # Computing shortest path
        shortestPath, pathCost = lower_bound_insertion(
            solution, TTGraph, TSGraph, bundle, suppNode, custNode;
        )
        lowerBound += pathCost
        # Adding to solution
        update_solution!(solution, instance, [bundle], [shortestPath]; sorted=true)
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i * 100 / length(instance.bundles)))% ")
    end
    println("\nLower Bound Computed : $lowerBound")
    return lowerBound
end

function parrallel_lower_bound!(solution::Solution, instance::Instance)
    lowerBound = 0.0
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Sorting commodities in orders and bundles between them
    sort_order_content!(instance)
    # Computing the lower bound delivery for each bundle
    # TODO : parrallelize here with native @threads
    #       deepcopy travel time graph
    #       compute lower bound insertion
    #       write shortest path at bundle idx or collect paths and costs to avoid false sharing
    # update solution all together
    # cut the instance by bundles and merge them at the end
    println("Lower Bound Computed : $lowerBound")
    return lowerBound
end

# Compute the path needed for filtering procedure
function lower_bound_filtering_path(
    TTGraph::TravelTimeGraph, TSGraph::TimeSpaceGraph, bundle::Bundle, src::Int, dst::Int
)
    # println("Before matrix update")
    # println("Has path : $(has_path(TTGraph.graph, src, dst))")
    # dijkstraState = dijkstra_shortest_paths(TTGraph.graph, src, TTGraph.costMatrix)
    # println("Shortest path : $(enumerate_paths(dijkstraState, dst))")
    update_lb_filtering_cost_matrix!(TTGraph, TSGraph, bundle)
    dijkstraState = dijkstra_shortest_paths(TTGraph.graph, src, TTGraph.costMatrix)
    shortestPath = enumerate_paths(dijkstraState, dst)
    # println("After matrix update")
    # println("Has path : $(has_path(TTGraph.graph, src, dst))")
    # println("Shortest path : $(enumerate_paths(dijkstraState, dst))")
    removedCost = remove_shortcuts!(shortestPath, TTGraph)
    pathCost = dijkstraState.dists[dst]
    return shortestPath, pathCost - removedCost
end

# Compute the solution for the filtering procedure
function lower_bound_filtering!(solution::Solution, instance::Instance)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Sorting commodities in orders and bundles between them
    sort_order_content!(instance)
    # Computing the lower bound delivery for each bundle
    println("Lower Bound filtering insertion progress : ")
    percentIdx = ceil(Int, length(instance.bundles) / 100)
    for (i, bundle) in enumerate(instance.bundles)
        # Retrieving bundle start and end nodes
        suppNode = TTGraph.bundleSrc[bundle.idx]
        custNode = TTGraph.bundleDst[bundle.idx]
        if !has_path(TTGraph.graph, suppNode, custNode)
            throw(
                ErrorException(
                    "Bundle $bundle does not have a path between supplier $suppNode ($(TTGraph.networkNodes[suppNode]) $(TTGraph.stepToDel[suppNode]) steps from delivery) and customer $custNode ($(TTGraph.networkNodes[custNode]) $(TTGraph.stepToDel[custNode]) steps from delivery)",
                ),
            )
        end
        # Computing shortest path
        shortestPath, pathCost = lower_bound_filtering_path(
            TTGraph, TSGraph, bundle, suppNode, custNode;
        )
        if length(shortestPath) == 0
            throw(
                ErrorException(
                    "No path found for bundle $bundle between supplier $suppNode ($(TTGraph.networkNodes[suppNode]) $(TTGraph.stepToDel[suppNode]) steps from delivery) and customer $custNode ($(TTGraph.networkNodes[custNode]) $(TTGraph.stepToDel[custNode]) steps from delivery)",
                ),
            )
        end
        # Adding to solution
        update_solution!(solution, instance, bundle, shortestPath; sorted=true)
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i * 100 / length(instance.bundles)))% ")
    end
    return println()
end

# TODO : like lower bound, this can be parrallelized