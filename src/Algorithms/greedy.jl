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
    dijkstraState = dijkstra_shortest_paths(TTGraph.graph, src, TTGraph.costMatrix)
    shortestPath = enumerate_paths(dijkstraState, dst)
    removedCost = remove_shortcuts!(shortestPath, TTGraph)
    pathCost = dijkstraState.dists[dst]
    return shortestPath, pathCost - removedCost
end

function greedy_path3(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int,
    CHANNEL::Channel{Vector{Int}},
    use_bins::Bool=true,
    opening_factor::Float64=1.0,
)
    # The remaining garbage collecting and runtime dispatch are caused by the parallelism
    parallel_update_cost_matrix2!(
        solution, TTGraph, TSGraph, bundle, CHANNEL, true, use_bins, opening_factor
    )
    # Most of the garbage collecting happens here 
    # Fix : recode a version where the obejcts used (alwayse the same) are passed to the function
    dijkstraState = dijkstra_shortest_paths(TTGraph.graph, src, TTGraph.costMatrix)
    shortestPath = enumerate_paths(dijkstraState, dst)
    removedCost = remove_shortcuts!(shortestPath, TTGraph)
    pathCost = dijkstraState.dists[dst]
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
    CHANNEL::Channel{Vector{Int}};
    verbose::Bool=false,
)
    verbose && println("Greedy insertion for bundle $bundle between src $src and dst $dst")
    verbose && println("Bundle arcs : $(TTGraph.bundleArcs[bundle.idx])")
    shortestPath, pathCost = greedy_path3(
        solution, TTGraph, TSGraph, bundle, src, dst, CHANNEL, true, 1.0
    )
    verbose && println("Initial path : $shortestPath for cost $pathCost")
    # If the path is not admissible, re-computing it
    if !is_path_admissible(TTGraph, shortestPath)
        # First trying to halve cost for the path computation
        costMatrix = deepcopy(TTGraph.costMatrix)
        shortestPath, pathCost = greedy_path3(
            solution, TTGraph, TSGraph, bundle, src, dst, CHANNEL, true, 0.5
        )
        if !is_path_admissible(TTGraph, shortestPath)
            # Then not taking into account the current solution
            # If this happens, we want to be sure to have an admissible path
            shortestPath, pathCost = greedy_path3(
                solution, TTGraph, TSGraph, bundle, src, dst, CHANNEL, false, 1.0
            )
            if !is_path_admissible(TTGraph, shortestPath)
                # println("Switching to distance based path")
                for (aSrc, aDst) in TTGraph.bundleArcs[bundle.idx]
                    TTGraph.costMatrix[aSrc, aDst] =
                        TTGraph.networkArcs[aSrc, aDst].distance
                end
                dijkstraState = dijkstra_shortest_paths(
                    TTGraph.graph, src, TTGraph.costMatrix
                )
                shortestPath = enumerate_paths(dijkstraState, dst)
                removedCost = remove_shortcuts!(shortestPath, TTGraph)
                print(" X3 ")
            else
                print(" X2 ")
            end
        else
            print(" X1 ")
        end
        pathCost = path_cost(shortestPath, costMatrix)
    end
    return shortestPath, pathCost
end

function debug_insertion(
    instance::Instance,
    solution::Solution,
    bundle::Bundle,
    shortestPath::Vector{Int},
    CHANNEL::Channel{Vector{Int}},
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Reverting solution 
    update_solution!(solution, instance, bundle, shortestPath; remove=true)
    solution2 = solution_deepcopy(solution, instance)
    # Re-doing the cost computation and updating 
    open("debug.txt", "w") do file
        redirect_stdout(file) do

            # Inserting it back
            suppNode = TTGraph.bundleSrc[bundle.idx]
            custNode = TTGraph.bundleDst[bundle.idx]
            newPath, pathCost = greedy_insertion(
                solution,
                TTGraph,
                TSGraph,
                bundle,
                suppNode,
                custNode,
                CHANNEL;
                verbose=true,
            )
            println("#############################################################")
            println("\n\nNew path : $newPath with cost $pathCost\n\n")
            println("#############################################################")

            # TODO : mettre en parallèle ici le cout d'update en version 2 pour voir direct les différences
            fullTentativeCost = 0.0
            fullActualCost = 0.0
            for (aSrc, aDst) in partition(newPath, 2, 1)
                println(
                    "\nIs update candidate : $(is_update_candidate(TTGraph, aSrc, aDst, bundle))",
                )
                println("Computing tenetaive cost for arc $aSrc -> $aDst")
                arcUpdateCost = arc_update_cost(
                    solution,
                    TTGraph,
                    TSGraph,
                    bundle,
                    aSrc,
                    aDst,
                    Int[];
                    sorted=true,
                    verbose=true,
                )
                fullTentativeCost += arcUpdateCost
                println("\nComputed cost for arc $aSrc -> $aDst : $arcUpdateCost")
                println(
                    "Reference cost for arc $aSrc -> $aDst : $(TTGraph.costMatrix[aSrc, aDst])",
                )

                actualUpdateCost = update_arc_bins!(
                    solution2, TSGraph, TTGraph, bundle, aSrc, aDst; verbose=true
                )
                fullActualCost += actualUpdateCost
                println("\nActual Computed cost for arc $aSrc -> $aDst : $actualUpdateCost")
            end

            println("#############################################################")
            println(
                "\n\n Full recomputed path cost : $fullTentativeCost \nFull recomputed actual cost : $fullActualCost \n\n",
            )
            println("#############################################################")

            updateCost = update_solution!(
                solution, instance, bundle, newPath; sorted=true, verbose=true
            )

            println("#############################################################")
            println("\n\nFull Update cost : $updateCost\n\n")
            println("#############################################################")

            updateCost2 = update_bins2!(
                solution2, TSGraph, TTGraph, bundle, newPath; sorted=true, verbose=true
            )

            println("#############################################################")
            println("\n\nFull Update cost 2 : $updateCost2\n\n")
            println("#############################################################")
        end
    end
    # Throwing error
    throw("Computed path cost and update cost don't match")
end

function greedy!(solution::Solution, instance::Instance; mode::Int=1)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Sorting commodities in orders and bundles between them
    sort_order_content!(instance)
    sortedBundleIdxs = sortperm(instance.bundles; by=bun -> bun.maxPackSize, rev=true)
    # Computing the greedy delivery possible for each bundle
    totalCost, totalPathCost = 0.0, 0.0
    print("Greedy introduction progress : ")
    CAPACITIES = Int[]
    CHANNEL = create_filled_channel()
    percentIdx = ceil(Int, length(sortedBundleIdxs) / 100)
    for (i, bundleIdx) in enumerate(sortedBundleIdxs)
        bundle = instance.bundles[bundleIdx]
        # Retrieving bundle start and end nodes
        suppNode = TTGraph.bundleSrc[bundleIdx]
        custNode = TTGraph.bundleDst[bundleIdx]
        # Computing shortest path
        shortestPath, pathCost = greedy_insertion(
            solution, TTGraph, TSGraph, bundle, suppNode, custNode, CHANNEL
        )
        totalPathCost += pathCost
        # Adding to solution
        updateCost = update_solution!(solution, instance, bundle, shortestPath; sorted=true)
        # verification
        if !isapprox(updateCost, pathCost; atol=1.0)
            debug_insertion(instance, solution, bundle, shortestPath, CHANNEL)
        end
        totalCost += updateCost
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i/ percentIdx))% ")
    end
    println()
    if !approx(totalPathCost, totalCost; atol=1.0)
        @warn "Computed path cost and update cost don't match" totalPathCost totalCost
    end
    return totalCost
end

function enforce_strict_admissibility!(solution::Solution, instance::Instance)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Computing the greedy delivery possible for each bundle
    print("Enforcing strict admissibility : ")
    CHANNEL = create_filled_channel()
    percentIdx = ceil(Int, length(instance.bundles) / 100)
    for (i, bundle) in enumerate(instance.bundles)
        bunPath = solution.bundlePaths[bundle.idx]
        # Recomputing if not admissible
        if !is_path_admissible(TTGraph, bunPath)
            # Retrieving bundle start and end nodes
            suppNode = TTGraph.bundleSrc[bundle.idx]
            custNode = TTGraph.bundleDst[bundle.idx]
            # Computing shortest path
            shortestPath, pathCost = greedy_insertion(
                solution, TTGraph, TSGraph, bundle, suppNode, custNode, CHANNEL
            )
            # Adding to solution
            updateCost = update_solution!(
                solution, instance, bundle, shortestPath; sorted=true
            )
            # verification
            if !isapprox(updateCost, pathCost; atol=1.0)
                debug_insertion(instance, solution, bundle, shortestPath, CHANNEL)
            end
        end
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i/ percentIdx))% ")
    end
    return println()
end