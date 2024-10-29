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

# Switching from Dijkstra to A* is clearly not a priority for now 

# TODO : if update cost matrix is really expensive, do it once with every option and store all option results in different objects

# Compute path and cost for the greedy insertion of a bundle, not handling path admissibility
function greedy_path(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int};
    sorted::Bool=false,
    use_bins::Bool=true,
    opening_factor::Float64=1.0,
    current_cost::Bool=false,
    findSources::Bool=true,
)
    # TODO : uncomment for tests with real instances
    # startTime = time()
    update_cost_matrix!(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        CAPACITIES;
        sorted=sorted,
        use_bins=use_bins,
        opening_factor=opening_factor,
        current_cost=current_cost,
        findSources=findSources,
    )
    # computeTime = time() - startTime
    # TODO : garbage collecting in here, need to recode dijkstra_shortest_paths ?
    dijkstraState = dijkstra_shortest_paths(TTGraph.graph, src, TTGraph.costMatrix)
    shortestPath = enumerate_paths(dijkstraState, dst)
    removedCost = remove_shortcuts!(shortestPath, TTGraph)
    pathCost = dijkstraState.dists[dst]

    # ARC_COSTS = fill(EPS, length(TTGraph.bundleArcs[bundle.idx]))
    # CHANNEL = create_channel(Vector{Int})
    # # Filling channel vectors with the content they could have (removing the allocation time from the benchmark)
    # for i in 1:Threads.nthreads() 
    #     buffer = take!(CHANNEL)
    #     append!(buffer, CAPACITIES)
    #     put!(CHANNEL, buffer)
    # end
    # startTime = time()
    # parallel_update_cost_matrix!(solution, TTGraph, TSGraph, bundle, CHANNEL, ARC_COSTS)
    # computeTime2 = time() - startTime
    # dijkstraState2 = dijkstra_shortest_paths(TTGraph.graph, src, TTGraph.costMatrix)
    # shortestPath2 = enumerate_paths(dijkstraState2, dst)
    # removedCost2 = remove_shortcuts!(shortestPath2, TTGraph)
    # pathCost2 = dijkstraState2.dists[dst]

    # @assert shortestPath == shortestPath2
    # @assert pathCost ≈ pathCost2
    # computeTime2 < computeTime ? print("O") : print("X")

    return shortestPath, pathCost - removedCost
end

# TODO : this recompuation happens rarely in the greedy heuristic but maybe more in the local search
# Compute the path and cost for the greedy insertion of a bundle, handling path admissibility
function greedy_insertion(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int};
    sorted::Bool=false,
    current_cost::Bool=false,
    findSources::Bool=true,
)
    shortestPath, pathCost = greedy_path(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        src,
        dst,
        CAPACITIES;
        sorted=sorted,
        use_bins=true,
        current_cost=current_cost,
        findSources=findSources,
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
            dst,
            CAPACITIES;
            sorted=sorted,
            use_bins=true,
            opening_factor=0.5,
            current_cost=current_cost,
            findSources=findSources,
        )
        if !is_path_admissible(TTGraph, shortestPath)
            # Then not taking into account the current solution
            # If this happens, we want to be sure to have an admissible path
            shortestPath, pathCost = greedy_path(
                solution,
                TTGraph,
                TSGraph,
                bundle,
                src,
                dst,
                CAPACITIES;
                sorted=sorted,
                use_bins=false,
                current_cost=false,
                findSources=findSources,
            )
            if !is_path_admissible(TTGraph, shortestPath)
                println("\nAll tentative path were non admissible")
                println("Bundle $bundle")
                println(
                    "Bundle src and dst : $(TTGraph.bundleSrc[bundle.idx])-$(TTGraph.bundleDst[bundle.idx])",
                )
                println("Path src and dst : $src-$dst")
                println("Path nodes : $shortestPath")
                println(
                    "Path info : $(join(string.(map(n -> TTGraph.networkNodes[n], shortestPath)), ", "))",
                )
                # shortestPath = [src, dst]
                # @assert is_path_admissible(TTGraph, shortestPath)
                # direct arc between two random nodes may not exist
                # TODO : Need to switch to constrained shortest paths ?
            end
        end
        pathCost = path_cost(shortestPath, costMatrix)
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
    print("Greedy introduction progress : ")
    CAPACITIES = Int[]
    percentIdx = ceil(Int, length(sortedBundleIdxs) / 100)
    for (i, bundleIdx) in enumerate(sortedBundleIdxs)
        bundle = instance.bundles[bundleIdx]
        # Retrieving bundle start and end nodes
        suppNode = TTGraph.bundleSrc[bundleIdx]
        custNode = TTGraph.bundleDst[bundleIdx]
        # Computing shortest path
        shortestPath, pathCost = greedy_insertion(
            solution, TTGraph, TSGraph, bundle, suppNode, custNode, CAPACITIES; sorted=true
        )
        # Adding to solution
        updateCost = update_solution!(solution, instance, bundle, shortestPath; sorted=true)
        # verification
        @assert isapprox(pathCost, updateCost; atol=50 * EPS) "Path cost ($pathCost) and Update cost ($updateCost) don't match \n bundle : $bundle ($suppNode - $custNode) \n shortestPath : $shortestPath \n bundleIdx : $bundleIdx"
        totalCost += updateCost
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i * percentIdx))% ")
    end
    println()
    return totalCost
end

function enforce_strict_admissibility!(solution::Solution, instance::Instance)
    # TODO : like clean_bins but for strict admissibility of paths, to be used at the end of the optimization, just before extraction
    # For all paths that are not strictly admissible, recomputing a greedy path 

    # if !is_path_admissible(instance.travelTimeGraph, path)
    #     if verbose
    #         @warn "Infeasible solution : path $path is not admissible"
    #     end
    #     return false
    # end
end