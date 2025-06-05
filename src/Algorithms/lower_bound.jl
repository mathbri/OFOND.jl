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

# Ideas to get a better lower bound :
# - for direct and non linear outsource, compute exact bin packing costs 
# - switch to lagragian relaxation instead of LP to scale the load plan design lower bound

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
        update_solution!(solution, instance, bundle, shortestPath; sorted=true)
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i / percentIdx))% ")
    end
    println("\nLower Bound Computed : $lowerBound")
    return lowerBound
end

function parallel_lower_bound!(solution::Solution, instance::Instance)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Sorting commodities in orders and bundles between them
    sort_order_content!(instance)
    # Creating a chennel to not write on the same matrix for each bundle treated in parallel
    CHANNEL = Channel{TravelTimeGraph}(Threads.nthreads())
    I, J, costs = findnz(TTGraph.costMatrix)
    _, _, Arcs = findnz(TTGraph.networkArcs)
    for _ in 1:Threads.nthreads()
        # Creating a travel time graph that only have independant cost matrix
        put!(CHANNEL, TravelTimeGraph(TTGraph, I, J, Arcs, costs))
    end

    # Using tmap() of OhMyThreads to parallelize
    println("Lower Bound computation (parrallel version so no progress bar)")
    pathAndCosts = tmap(Tuple{Vector{Int},Float64}, instance.bundles) do bundle
        TTGRAPH = take!(CHANNEL)
        suppNode = TTGraph.bundleSrc[bundle.idx]
        custNode = TTGraph.bundleDst[bundle.idx]
        # Computing shortest path
        result = lower_bound_insertion(
            solution, TTGraph, TSGraph, bundle, suppNode, custNode;
        )
        put!(CHANNEL, TTGRAPH)
        result
    end

    # Computing lower bound
    lowerBound = sum(x -> x[2], pathAndCosts)
    # Updating solution with the paths computed 
    update_solution!(
        solution, instance, instance.bundles, [x[1] for x in pathAndCosts]; sorted=true
    )
    println("Lower Bound Computed : $lowerBound")
    return lowerBound
end

function parallel_lower_bound2!(solution::Solution, instance::Instance)
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
        parallel_update_lb_cost_matrix!(solution, TTGraph, TSGraph, bundle, false, false)
        dijkstraState = dijkstra_shortest_paths(TTGraph.graph, suppNode, TTGraph.costMatrix)
        shortestPath = enumerate_paths(dijkstraState, custNode)
        removedCost = remove_shortcuts!(shortestPath, TTGraph)
        pathCost = dijkstraState.dists[custNode] - removedCost
        lowerBound += pathCost
        # Adding to solution
        update_solution!(solution, instance, [bundle], [shortestPath]; sorted=true)
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i / percentIdx))% ")
    end
    println("\nLower Bound Computed : $lowerBound")
    return lowerBound
end

# Compute the path needed for filtering procedure
function lower_bound_filtering_path(
    TTGraph::TravelTimeGraph, TSGraph::TimeSpaceGraph, bundle::Bundle, src::Int, dst::Int
)
    update_lb_filtering_cost_matrix!(TTGraph, TSGraph, bundle)
    dijkstraState = dijkstra_shortest_paths(TTGraph.graph, src, TTGraph.costMatrix)
    shortestPath = enumerate_paths(dijkstraState, dst)
    remove_shortcuts!(shortestPath, TTGraph)
    return shortestPath
end

# Compute the solution for the filtering procedure
function lower_bound_filtering!(solution::Solution, instance::Instance)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Sorting commodities in orders and bundles between them
    sort_order_content!(instance)
    # Computing the lower bound delivery for each bundle
    println("Lower Bound filtering insertion progress : ")
    percentIdx = ceil(Int, length(instance.bundles) / 100)
    barIdx = ceil(Int, percentIdx / 10)
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
        shortestPath = lower_bound_filtering_path(
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
        i % barIdx == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i / percentIdx))% ")
    end
    return println()
end

# If there is too much garbage collecting associated with graph creation, make specialized version of the functions just for the cost matrix

function parallel_lower_bound_filtering!(solution::Solution, instance::Instance)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Sorting commodities in orders and bundles between them
    sort_order_content!(instance)
    # Creating a chennel to not write on the same matrix for each bundle treated in parallel
    CHANNEL = Channel{TravelTimeGraph}(Threads.nthreads())
    I, J, costs = findnz(TTGraph.costMatrix)
    _, _, Arcs = findnz(TTGraph.networkArcs)
    for _ in 1:Threads.nthreads()
        # Creating a travel time graph that only have independant cost matrix
        put!(CHANNEL, TravelTimeGraph(TTGraph, I, J, Arcs, costs))
    end

    println("Lower Bound Filtering computation (parrallel version so no progress bar)")
    paths = tmap(Vector{Int}, instance.bundles) do bundle
        TTGRAPH = take!(CHANNEL)
        suppNode = TTGraph.bundleSrc[bundle.idx]
        custNode = TTGraph.bundleDst[bundle.idx]
        # Computing shortest path
        result = lower_bound_filtering_path(TTGraph, TSGraph, bundle, suppNode, custNode)
        put!(CHANNEL, TTGRAPH)
        result
    end

    # Updating solution with the paths computed 
    update_solution!(solution, instance, instance.bundles, paths; sorted=true)
    return println()
end

function parallel_lower_bound_filtering2!(solution::Solution, instance::Instance)
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
        # Computing shortest path
        parallel_update_lb_filtering_cost_matrix!(TTGraph, TSGraph, bundle)
        dijkstraState = dijkstra_shortest_paths(TTGraph.graph, suppNode, TTGraph.costMatrix)
        shortestPath = enumerate_paths(dijkstraState, custNode)
        remove_shortcuts!(shortestPath, TTGraph)
        # Adding to solution
        update_solution!(solution, instance, bundle, shortestPath; sorted=true)
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i / percentIdx))% ")
    end
    return println()
end