# TODO : add a random delivery mode option (in arc cost ? direct or outsource ?)

# For every bundle :
#     Compute network arc cost, either precomputed ffd bin-packing or volume * linear cost
#     Compute the shortest path from supplier to customer on the netwotk graph
#     Store bundle path in Solution object
#     Update time space graph :
#         For all arc in the path, update timed arcs loading with the corresponding bundle order content 

# Construct and return solution object

# Benchmark heuristic where all bundle path are computed as the shortest delivery path on the network graph
function shortest_delivery_heuristic(instance::Instance)
    startTime = time()
    # Build travel time and time space graphs from instance
    travelTimeGraph, travelTimeUtils = build_travel_time_and_utils(instance.networkGraph, instance.bundles)
    timeSpaceGraph, timeSpaceUtils = build_time_space_and_utils(instance.networkGraph, instance.timeHorizon)
    bundlePaths = Vector{Vector{Int}}()

    # Saving pre-solve time
    preSolveTime = round((time() - startTime) * 1000) / 1000
    println("Pre-solve time : $preSolveTime s")
    
    # Computing the shortest delivery possible for each bundle
    for (bundleIdx, bundle) in enumerate(instance.bundles)
        # Retrieving bundle start and end nodes
        suppNode = travelTimeUtils.bundleStartNodes[bundleIdx]
        custNode = travelTimeUtils.bundleEndNodes[bundleIdx]
        # Computing shortest path
        shortestPath = a_star(travelTimeGraph, suppNode, custNode, travelTimeUtils.costMatrix)
        # Adding shortest path to all bundle paths
        push!(bundlePaths, path)
        # Updating the bins for each order of the bundle
        for order in bundle.orders
            update_bins!(timeSpaceGraph, travelTimeGraph, path, bundle)
        end
    end

    # Saving solve time
    solveTime = round((time() - preSolveTime) * 1000) / 1000
    println("solve time : $solveTime s")

    return Solution(travelTimeGraph, bundlePaths, timeSpaceGraph)
end