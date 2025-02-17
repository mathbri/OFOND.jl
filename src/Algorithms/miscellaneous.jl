###########################################################################################
#################################   First heuristics   ####################################
###########################################################################################

# Benchmark heuristic where all bundle path are computed as the shortest delivery path on the network graph
function shortest_delivery!(solution::Solution, instance::Instance)
    totCost = 0.0
    # Reconstructing TTGraph to have all entries of the cost matrix to EPS
    TTGraph = TravelTimeGraph(instance.networkGraph, instance.bundles)
    # Sorting commodities
    sort_order_content!(instance)
    # Computing the shortest delivery possible for each bundle
    for bundle in instance.bundles
        # Retrieving bundle start and end nodes
        suppNode = TTGraph.bundleSrc[bundle.idx]
        custNode = TTGraph.bundleDst[bundle.idx]
        # Computing shortest path
        shortestPath = enumerate_paths(
            dijkstra_shortest_paths(TTGraph.graph, suppNode, TTGraph.costMatrix), custNode
        )
        # Adding to solution
        totCost += update_solution!(solution, instance, bundle, shortestPath; sorted=true)
    end
    return totCost
end

# Benchmark heuristic where all bundle path are computed as the minimum cost average delivery using giant trucks approximation for consolidated arcs
# Can be seen as greedy on the relaxation using averaged bundles
function average_delivery!(solution::Solution, instance::Instance)
    # First step : transforming bundles by averaging bundles orders 
    netGraph, timeHorizon = instance.networkGraph, instance.timeHorizon
    avgBundles = Bundle[
        add_properties(average_bundle(bundle, timeHorizon), netGraph) for
        bundle in instance.bundles
    ]
    for avgBun in avgBundles
        for (o, order) in enumerate(avgBun.orders)
            avgBun.orders[o] = add_properties(order, tentative_first_fit, Int[])
        end
    end
    # Second step : use the already prepared lower bound cost matrix update 
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    totCost = 0.0
    # Sorting commodities
    sort_order_content!(instance)
    # Computing the average delivery
    for (bundle, avgBundle) in zip(instance.bundles, avgBundles)
        # Retrieving bundle start and end nodes
        bSrc = TTGraph.bundleSrc[bundle.idx]
        bDst = TTGraph.bundleDst[bundle.idx]
        # Computing shortest path
        shortestPath, pathCost = lower_bound_insertion(
            solution, TTGraph, TSGraph, avgBundle, bSrc, bDst; use_bins=true, giant=true
        )
        # Adding to solution
        totCost += update_solution!(solution, instance, bundle, shortestPath; sorted=true)
    end
    return totCost
end

# Benchmark heuristic where all bundle path are computed as the minimum cost delivery using random costs on arcs
function random_delivery!(
    solution::Solution, instance::Instance; nSol::Int=10, check::Bool=false
)
    TTGraph = instance.travelTimeGraph
    # Sorting commodities
    sort_order_content!(instance)
    # Computing the best solution in nSol random solutions 
    solutions = Solution[Solution(instance) for _ in 1:nSol]
    costs = Float64[]
    for sol in solutions
        solCost = 0.0
        # Updating costs matrix (1e5 to put every arc cost to 1 and then rand() to put it between 0 and 1)
        TTGraph.costMatrix .*= 1e5 .* rand(Float64, size(TTGraph.costMatrix))
        # Computing the best random deliveries for each bundle
        for bundle in instance.bundles
            # Retrieving bundle start and end nodes
            suppNode = TTGraph.bundleSrc[bundle.idx]
            custNode = TTGraph.bundleDst[bundle.idx]
            # Computing shortest path
            shortestPath = enumerate_paths(
                dijkstra_shortest_paths(TTGraph.graph, suppNode, TTGraph.costMatrix),
                custNode,
            )
            # Adding to solution
            solCost += update_solution!(sol, instance, bundle, shortestPath; sorted=true)
        end
        push!(costs, solCost)
        print("|")
        # Checking computations
        if check
            @assert is_feasible(instance, sol)
        end
    end
    println()
    # Updating the best has the current solution
    bestSol = solutions[argmin(costs)]
    return update_solution!(
        solution, instance, instance.bundles, bestSol.bundlePaths; sorted=true
    )
end

###########################################################################################
###############################   MILP based heuristics   #################################
###########################################################################################

function full_perturbation(instance::Instance)
    emptySol = Solution(instance)
    shortest_delivery!(emptySol, instance)
    bundleIdxs = idx(instance.bundles)
    oldPaths = emptySol.bundlePaths
    loads = map(bins -> 0, emptySol.bins)
    return Perturbation(:arc_flow, bundleIdxs, oldPaths, loads)
end

# Construct a lower bound MILP on the full instance
function full_lower_bound_milp(instance::Instance; withPacking::Bool=true)
    # Creating an arc flow perturbation with all bundles 
    perturbation = full_perturbation(instance)
    model = model_with_optimizer(; timeLimit=60.0, verbose=true)
    add_variables!(model, instance, perturbation)
    # Putting the current cost back to default unit costs
    slope_scaling_cost_update!(instance.timeSpaceGraph, Solution(instance))
    add_objective!(model, instance, perturbation)
    if !withPacking
        for key in eachindex(model[:tau])
            delete(model, model[:tau][key])
        end
        unregister(model, :tau)
    end
    @info "MILP has $(num_variables(model)) variables ($(count(is_binary, all_variables(model))) binary and $(count(is_integer, all_variables(model))) integer)"
    add_path_constraints!(model, instance, perturbation)
    if withPacking
        add_packing_constraints!(model, instance, perturbation)
        # add_cut_set_inequalities!(model, instance)
        @info "MILP has $(num_constraints(model; count_variable_in_set_constraints=false)) constraints ($(length(model[:path])) path, $(length(model[:packing])) packing)"
    else
        @info "MILP has $(num_constraints(model; count_variable_in_set_constraints=false)) constraints (path)"
    end
    return model
end

# Compute a lower bound thanks to the MILP machinery of the lns
function milp_lower_bound!(solution::Solution, instance::Instance; verbose::Bool=false)
    println("MILP lower bound construction")
    # Buidling model
    model = full_lower_bound_milp(instance)
    # Getting bound
    optimize!(model)
    objBound = objective_bound(model)
    println("Lower bound computed = $objBound")
    # Getting the solution paths (if any)
    if has_values(model)
        perturbation = full_perturbation(instance)
        newPaths = get_paths(model, instance, perturbation)
        sort_order_content!(instance)
        update_solution!(solution, instance, instance.bundles, newPaths; sorted=true)
    else
        # If no path computed, returning a shortest delivery solution 
        shortest_delivery!(solution, instance)
    end
    return objBound
end

# The perturbations in arc flow formulations like plant, random and supplier are also heuristics to use as benchmark 

function plant_by_plant_milp!(solution::Solution, instance::Instance)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    totCost = 0.0
    emptySol = Solution(instance)
    shortest_delivery!(emptySol, instance)
    # Sorting commodities
    sort_order_content!(instance)
    # Gathering all plants
    plants = findall(node -> node.type == :plant, TTGraph.networkNodes)
    # Going through all plants in random order to select one
    for (i, plant) in enumerate(shuffle(plants))
        bunIdxs = findall(dst -> dst == plant, TTGraph.bundleDst)
        # If no bundle for this plant, skipping to another directly
        length(bunIdxs) == 0 && continue
        @info "Treating plant : $plant ($i / $(length(plants)))"
        # If too much bundles, seperating into smaller groups
        nCommon = length(TSGraph.commonArcs)
        nVar = nCommon + sum(length(TTGraph.bundleArcs[b]) for b in bunIdxs)
        nGroups = ceil(Int, nVar / (MAX_MILP_VAR - nCommon))
        nPart = ceil(Int, length(bunIdxs) / nGroups)
        for bunGroupIdxs in partition(bunIdxs, nPart)
            bunGroupIdxs = collect(bunGroupIdxs)
            # Computing paths for the whole group
            perturbation = arc_flow_perturbation(instance, emptySol, bunGroupIdxs)
            bunPaths = solve_lns_milp(instance, perturbation; warmStart=false, verbose=true)
            # Adding to solution
            bunGroup = instance.bundles[bunGroupIdxs]
            totCost += update_solution!(solution, instance, bunGroup, bunPaths; sorted=true)
            println("Bundles added : $(length(bunGroup))")
        end
    end
    return totCost
end

function customer_by_customer_milp!(solution::Solution, instance::Instance)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    totCost = 0.0
    emptySol = Solution(instance)
    shortest_delivery!(emptySol, instance)
    # Sorting commodities
    sort_order_content!(instance)
    suppliers = findall(node -> node.type == :supplier, TTGraph.networkNodes)
    filter!(sup -> TTGraph.stepToDel[sup] == 0, suppliers)
    # Going through all suppliers in random order to select one
    for (i, supplier) in enumerate(shuffle(suppliers))
        # Getting all bundle sharing the same supplier, possibly with different start date
        supplierNode = TTGraph.networkNodes[supplier]
        bunIdxs = findall(
            bunSrc -> TTGraph.networkNodes[bunSrc] == supplierNode, TTGraph.bundleSrc
        )
        # If no bundle for this plant, skipping to another directly
        length(bunIdxs) == 0 && continue
        @info "Treating supplier : $supplier ($i / $(length(suppliers)))"
        # No chance of having too much variables in this context
        perturbation = arc_flow_perturbation(instance, emptySol, bunIdxs)
        bunPaths = solve_lns_milp(instance, perturbation; warmStart=false)
        # Adding to solution
        bunGroup = instance.bundles[bunIdxs]
        totCost += update_solution!(solution, instance, bunGroup, bunPaths; sorted=true)
        println("Bundles added : $(length(bunGroup))")
    end
    return totCost
end

function random_by_random_milp!(solution::Solution, instance::Instance)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    totCost, i = 0.0, 1
    emptySol = Solution(instance)
    shortest_delivery!(emptySol, instance)
    allIdxs = shuffle(1:length(instance.bundles))
    # Sorting commodities
    sort_order_content!(instance)
    # Going through groups one after another
    while length(allIdxs) > 0
        # Constructing the group to work on
        bunGroupIdxs, nVar = [pop!(allIdxs)], length(TSGraph.commonArcs)
        while length(allIdxs) > 0 && nVar < MAX_MILP_VAR
            bIdx = allIdxs[end]
            if nVar + length(TTGraph.bundleArcs[bIdx]) <= MAX_MILP_VAR
                push!(bunGroupIdxs, pop!(allIdxs))
                nVar += length(TTGraph.bundleArcs[bIdx])
            end
        end
        # Computing paths for the whole group 
        @info "Treating random group $i ($(length(allIdxs)) bundles left)"
        perturbation = arc_flow_perturbation(instance, emptySol, bunGroupIdxs)
        bunPaths = solve_lns_milp(instance, perturbation; warmStart=false)
        # Adding to solution
        bunGroup = instance.bundles[bunGroupIdxs]
        totCost += update_solution!(solution, instance, bunGroup, bunPaths; sorted=true)
        println("Bundles added : $(length(bunGroup))")
    end
    return totCost
end

# Compute the full MILP formulation of the problem
function exact_milp!(solution::Solution, instance::Instance)
    # TODO
end

###########################################################################################
###########################   Mixing greedy and Lower Bound   #############################
###########################################################################################

# Construct at the same time the greedy and lower bound solution to allow the construction of the combination of both for free
function mix_greedy_and_lower_bound!(
    solution::Solution, instance::Instance; check::Bool=false
)
    # Initialize the other solution objects
    gSol, lbSol, B = Solution(instance), Solution(instance), length(instance.bundles)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Run the corresponding heuristics
    sort_order_content!(instance)
    sortedBundleIdxs = sortperm(instance.bundles; by=bun -> bun.maxPackSize, rev=true)
    # Computing the delivery possible for each bundle
    print("All introduction progress : ")
    CAPA, percentIdx = Int[], ceil(Int, B / 100)
    for (i, bundleIdx) in enumerate(sortedBundleIdxs)
        bundle = instance.bundles[bundleIdx]
        # Retrieving bundle start and end nodes
        bSrc = TTGraph.bundleSrc[bundleIdx]
        bDst = TTGraph.bundleDst[bundleIdx]
        # Computing greedy shortest path
        gPath, _ = greedy_insertion(
            gSol, TTGraph, TSGraph, bundle, bSrc, bDst, CAPA; sorted=true
        )
        update_solution!(gSol, instance, bundle, gPath; sorted=true)
        # Saving cost matrix 
        greedyCostMatrix = deepcopy(TTGraph.costMatrix)
        # Computing lower bound shortest path
        lbPath, _ = lower_bound_insertion(lbSol, TTGraph, TSGraph, bundle, bSrc, bDst)
        update_solution!(lbSol, instance, bundle, lbPath; sorted=true)
        # Computing mixed shortest path
        mixedCostMatrix = (i / B) .* greedyCostMatrix .+ (B - i / B) .* TTGraph.costMatrix
        dijkstraState = dijkstra_shortest_paths(TTGraph.graph, bSrc, mixedCostMatrix)
        shortestPath = enumerate_paths(dijkstraState, bDst)
        remove_shortcuts!(shortestPath, TTGraph)
        update_solution!(solution, instance, bundle, shortestPath; sorted=true)
        # Record progress
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i * percentIdx))% ")
        # Checking computations
        if check
            for (src, dst) in TTGraph.bundleArcs[bundleIdx]
                @assert mixedCostMatrix[src, dst] ≈
                    (i / B) * greedyCostMatrix[src, dst] +
                        (B - i / B) * TTGraph.costMatrix[src, dst]
            end
        end
    end
    println()
    return gSol, lbSol
end

###########################################################################################
#################################   Fully Outsourcing   ###################################
###########################################################################################

# TODO : if everything is linear, why not using the lower bound with dijkstra ?
# Can be used for now as a benchmark for the difference between lower bound with dijkstra and pure LP

# Why would a bundle use platforms if the cost is directly linear with distance ? Because the direct arcs are not linearized
# TODO : is it possible to have path with more than 2 arcs ?
# Modify the instance to transform it into a fully outsourced network and then compute a solution to this instance
function fully_outsourced!(solution::Solution, instance::Instance; maxPathLength::Int=-1)
    # Building the new instance costs
    newInstance = outsource_instance(instance)
    # Solution generation (it is a linear program now)
    model = full_lower_bound_milp(newInstance; withPacking=false)
    # Adding a path length constraint to two ? 
    # Either direct or going to one platform as the transporter is responsible for the rest
    if maxPathLength >= 1
        B, x = length(newInstance.bundles), model[:x]
        # Excluding shortcut arcs from this sum
        TTGraph = newInstance.travelTimeGraph
        b_arcs = b -> TTGraph.bundleArcs[b]
        is_shortcut = a -> TTGraph.networkArcs[a[1], a[2]] == SHORTCUT
        @constraint(
            model,
            pathLength[b in 1:B],
            sum(x[b, a] for a in b_arcs(b) if !is_shortcut(a)) <= maxPathLength
        )
    end
    # Optimizing and Getting paths
    optimize!(model)
    # Getting the solution paths (if any)
    if has_values(model)
        perturbation = full_perturbation(instance)
        newPaths = get_paths(model, newInstance, perturbation)
        sort_order_content!(newInstance)
        updateCost = update_solution!(
            solution, instance, instance.bundles, newPaths; sorted=true
        )
        println("Corresponding solution cost = $updateCost")
    else
        # If no path computed, returning a shortest delivery solution 
        shortest_delivery!(solution, instance)
    end
    return JuMP.objective_value(model) + 1e-5
end