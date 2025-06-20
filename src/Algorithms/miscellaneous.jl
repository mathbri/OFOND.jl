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
    print("Shortest delivery introduction progress : ")
    percentIdx = ceil(Int, length(instance.bundles) / 100)
    for (i, bundle) in enumerate(instance.bundles)
        # Retrieving bundle start and end nodes
        suppNode = TTGraph.bundleSrc[bundle.idx]
        custNode = TTGraph.bundleDst[bundle.idx]
        # Computing shortest path
        for (aSrc, aDst) in TTGraph.bundleArcs[bundle.idx]
            TTGraph.costMatrix[aSrc, aDst] = TTGraph.networkArcs[aSrc, aDst].distance
        end
        shortestPath = enumerate_paths(
            dijkstra_shortest_paths(TTGraph.graph, suppNode, TTGraph.costMatrix), custNode
        )
        # Adding to solution
        totCost += update_solution!(solution, instance, bundle, shortestPath; sorted=true)
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i/ percentIdx))% ")
    end
    println()
    return totCost
end

# Benchmark heuristic where all bundle path are computed as the minimum cost average delivery using giant trucks approximation for consolidated arcs
# Can be seen as greedy on the relaxation using averaged bundles
function average_delivery!(solution::Solution, instance::Instance)
    println("Averaging bundles")
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
    print("Average delivery introduction progress : ")
    percentIdx = ceil(Int, length(instance.bundles) / 100)
    for (i, (bundle, avgBundle)) in enumerate(zip(instance.bundles, avgBundles))
        # Retrieving bundle start and end nodes
        bSrc = TTGraph.bundleSrc[bundle.idx]
        bDst = TTGraph.bundleDst[bundle.idx]
        # Computing shortest path
        shortestPath, pathCost = lower_bound_insertion(
            solution, TTGraph, TSGraph, avgBundle, bSrc, bDst; use_bins=true, giant=true
        )
        # Adding to solution
        totCost += update_solution!(solution, instance, bundle, shortestPath; sorted=true)
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i/ percentIdx))% ")
    end
    println()
    return totCost
end

# Benchmark heuristic where all bundle path are computed as the minimum cost delivery using random costs on arcs
function random_delivery!(
    solution::Solution, instance::Instance; nSol::Int=5, check::Bool=false
)
    println("Generating $nSol random deliveries")
    TTGraph = instance.travelTimeGraph
    # Sorting commodities
    sort_order_content!(instance)
    # Computing the best solution in nSol random solutions 
    solutions = Solution[Solution(instance) for _ in 1:nSol]
    costs = Float64[]
    percentIdx = ceil(Int, length(instance.bundles) / 100)
    for (s, sol) in enumerate(solutions)
        solCost = 0.0
        print("Random delivery $s introduction progress : ")
        # Updating costs matrix (1e5 to put every arc cost to 1 and then rand() to put it between 0 and 1)
        TTGraph.costMatrix .*= 1e5 .* rand(size(TTGraph.costMatrix))
        # Computing the best random deliveries for each bundle
        for (i, bundle) in enumerate(instance.bundles)
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
            i % 10 == 0 && print("|")
            i % percentIdx == 0 && print(" $(round(Int, i/ percentIdx))% ")
        end
        println()
        push!(costs, solCost)
        # Checking computations
        if check
            @assert is_feasible(instance, sol)
        end
    end
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
function full_lower_bound_milp(
    instance::Instance; withPacking::Bool=true, withElementarity::Bool=true
)
    # Creating an arc flow perturbation with all bundles 
    perturbation = full_perturbation(instance)
    model = model_with_optimizer(; timeLimit=300.0, verbose=true)
    add_variables!(model, instance, perturbation)
    # Putting the current cost back to default unit costs
    slope_scaling_cost_update!(instance.timeSpaceGraph, Solution(instance))
    add_objective!(model, instance, perturbation; lowerBound=true)
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
        if withElementarity
            add_elementarity_constraints!(model, instance, perturbation)
            @info "MILP has $(num_constraints(model; count_variable_in_set_constraints=false)) constraints ($(length(model[:path])) path, $(length(model[:packing])) packing, $(length(model[:elementarity])) elementarity)"
        else
            @info "MILP has $(num_constraints(model; count_variable_in_set_constraints=false)) constraints ($(length(model[:path])) path, $(length(model[:packing])) packing)"
        end
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
        @warn "No solution found, only bound"
        # If no path computed, returning a shortest delivery solution 
        shortest_delivery!(solution, instance)
    end
    return objBound
end

function milp_lower_bound2!(solution::Solution, instance::Instance; verbose::Bool=false)
    println("MILP lower bound construction")
    # Buidling model
    model = full_lower_bound_milp(instance; withElementarity=true)
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
        # Comparing solutions
        # for arc in instance.timeSpaceGraph.commonArcs
        #     solBins = solution.bins[arc]
        #     nSolBins = length(solBins)
        #     nMilpBins = value(model[:tau][arc])
        #     if nSolBins - nMilpBins > 1
        #         println("Milp bins and Sol bins disagree")
        #         println("Arc $arc : $(instance.timeSpaceGraph.networkArcs[arc])")
        #         println("nMilpBins = $nMilpBins")
        #         println("nSolBins = $nSolBins")
        #         println(solBins)
        #         @assert nSolBins == nMilpBins
        #     end
        # end
    else
        @warn "No solution found, only bound"
        # If no path computed, returning a shortest delivery solution 
        shortest_delivery!(solution, instance)
    end
    return objBound
end

# The perturbations in arc flow formulations like plant, random and supplier are also heuristics to use as benchmark 

function plant_by_plant_milp!(solution::Solution, instance::Instance)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    totCost = 0.0
    # emptySol = Solution(instance)
    shortest_delivery!(solution, instance)
    # Sorting commodities
    sort_order_content!(instance)
    # Gathering all plants
    plants = findall(node -> node.type == :plant, TTGraph.networkNodes)
    # Going through all plants in random order to select one
    for (i, plant) in enumerate(shuffle(plants))
        @info "Treating plant : $plant ($i / $(length(plants)))"
        plantIdxs = findall(dst -> dst == plant, TTGraph.bundleDst)
        # If no bundle for this plant, skipping to another directly
        length(plantIdxs) == 0 && continue
        # If too much bundles, seperating into smaller groups
        nCommon, j = length(TSGraph.commonArcs), 1
        totGroups = ceil(
            Int,
            sum(length(TTGraph.bundleArcs[b]) for b in plantIdxs) /
            (MAX_MILP_VAR - nCommon),
        )
        while length(plantIdxs) > 0
            @info "Treating group : $j / $totGroups (plant $i / $(length(plants)))"
            nVars = cumsum([length(TTGraph.bundleArcs[b]) for b in plantIdxs])
            stopIdx = findlast(n -> n <= MAX_MILP_VAR - nCommon, nVars)
            bunGroupIdxs = plantIdxs[1:stopIdx]
            plantIdxs = plantIdxs[(stopIdx + 1):end]
            # Computing new paths
            perturbation = arc_flow_perturbation(instance, solution, bunGroupIdxs)
            bunPaths = solve_lns_milp(instance, perturbation; warmStart=false, verbose=true)
            # Adding to solution
            bunGroup = instance.bundles[bunGroupIdxs]
            totCost += update_solution!(solution, instance, bunGroup, bunPaths; sorted=true)
            println(
                "Bundles added : $(length(bunGroup)) (directs = $(count(x -> length(x) == 2, bunPaths)))",
            )
            j += 1
        end
        # nVar = nCommon + sum(length(TTGraph.bundleArcs[b]) for b in bunIdxs)
        # nGroups = ceil(Int, nVar / (MAX_MILP_VAR - nCommon))
        # nPart = ceil(Int, length(bunIdxs) / nGroups)
        # for bunGroupIdxs in partition(bunIdxs, nPart)
        #     bunGroupIdxs = collect(bunGroupIdxs)
        #     # Computing paths for the whole group
        #     perturbation = arc_flow_perturbation(instance, emptySol, bunGroupIdxs)
        #     bunPaths = solve_lns_milp(instance, perturbation; warmStart=false, verbose=true)
        #     # Adding to solution
        #     bunGroup = instance.bundles[bunGroupIdxs]
        #     totCost += update_solution!(solution, instance, bunGroup, bunPaths; sorted=true)
        #     println("Bundles added : $(length(bunGroup))")
        # end
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
    nCommon = length(TSGraph.commonArcs)
    while length(allIdxs) > 0
        # Constructing the group to work on
        # println("Contructing random group")
        nVars = cumsum([length(TTGraph.bundleArcs[b]) for b in allIdxs])
        # println("Cumsum computed")
        stopIdx = findlast(n -> n <= MAX_MILP_VAR - nCommon, nVars)
        # println("Stop idx computed")
        bunGroupIdxs = allIdxs[1:stopIdx]
        allIdxs = allIdxs[(stopIdx + 1):end]
        # println("All bundle idxs divided")
        # bunGroupIdxs, nVar = [pop!(allIdxs)], length(TSGraph.commonArcs)
        # while length(allIdxs) > 0 && nVar < MAX_MILP_VAR
        #     bIdx = allIdxs[end]
        #     if nVar + length(TTGraph.bundleArcs[bIdx]) <= MAX_MILP_VAR
        #         push!(bunGroupIdxs, pop!(allIdxs))
        #         nVar += length(TTGraph.bundleArcs[bIdx])
        #     end
        # end
        # Computing paths for the whole group 
        @info "Treating random group $i ($(length(allIdxs)) bundles left)"
        perturbation = arc_flow_perturbation(instance, solution, bunGroupIdxs)
        bunPaths = solve_lns_milp(
            instance, perturbation; warmStart=false, verbose=true, optVerbose=true
        )
        # Adding to solution
        bunGroup = instance.bundles[bunGroupIdxs]
        totCost += update_solution!(solution, instance, bunGroup, bunPaths; sorted=true)
        println(
            "Bundles added : $(length(bunGroup)) (directs = $(count(x -> length(x) == 2, bunPaths)))",
        )
        i += 1
    end
    return totCost
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
    CHANNEL = create_filled_channel()
    lowerBound = 0.0
    greedyCostMatrix = deepcopy(TTGraph.costMatrix)
    for (i, bundleIdx) in enumerate(sortedBundleIdxs)
        bundle = instance.bundles[bundleIdx]
        # Retrieving bundle start and end nodes
        bSrc = TTGraph.bundleSrc[bundleIdx]
        bDst = TTGraph.bundleDst[bundleIdx]
        # Computing greedy shortest path
        gPath, gCost = greedy_insertion2(
            gSol, TTGraph, TSGraph, bundle, bSrc, bDst, CHANNEL
        )
        upCost = update_solution!(gSol, instance, bundle, gPath; sorted=true)
        # verification
        if !isapprox(upCost, gCost; atol=1.0)
            debug_insertion(instance, gSol, bundle, gPath, CHANNEL)
        end
        # Saving cost matrix 
        for (src, dst) in TTGraph.bundleArcs[bundleIdx]
            greedyCostMatrix[src, dst] = TTGraph.costMatrix[src, dst]
        end
        # Computing lower bound shortest path
        lbPath, lbCost = lower_bound_insertion(lbSol, TTGraph, TSGraph, bundle, bSrc, bDst)
        lowerBound += lbCost
        update_solution!(lbSol, instance, bundle, lbPath; sorted=true)
        # Computing mixed shortest path
        mixedCostMatrix = (i / B) .* greedyCostMatrix .+ (B - i / B) .* TTGraph.costMatrix
        dijkstraState = dijkstra_shortest_paths(TTGraph.graph, bSrc, mixedCostMatrix)
        shortestPath = enumerate_paths(dijkstraState, bDst)
        remove_shortcuts!(shortestPath, TTGraph)
        update_solution!(solution, instance, bundle, shortestPath; sorted=true)
        # Record progress
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i / percentIdx))% ")
        # Checking computations
        if check
            for (src, dst) in TTGraph.bundleArcs[bundleIdx]
                @assert mixedCostMatrix[src, dst] ≈
                    (i / B) * greedyCostMatrix[src, dst] +
                        (B - i / B) * TTGraph.costMatrix[src, dst]
            end
        end
    end
    println("\nLower bound computed : $lowerBound")
    return gSol, lbSol
end

###########################################################################################
#################################   Fully Outsourcing   ###################################
###########################################################################################

# Can be used for now as a benchmark for the difference between lower bound with dijkstra and pure LP

# Why would a bundle use platforms if the cost is directly linear with distance ? Because the direct arcs are not linearized
# Is it possible to have path with more than 2 arcs (if there is a direct) ?
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

function fully_outsourced2!(solution::Solution, instance::Instance; maxPathLength::Int=-1)
    # Building the new instance costs
    newInstance = outsource_instance(instance)
    # Solution generation (it is a linear program now)
    lower_bound!(solution, newInstance)
    println("Fully outsourced cost = $(compute_cost(newInstance, solution))")
    return compute_cost(instance, solution)
end

###########################################################################################
#################################   Load Plan Design   ####################################
###########################################################################################

# The computation as it would be done for the load plan design problem (erera et al. for example)
# Need solving perturbation milps but also retrieving the objective of the milp bound

function load_plan_design_arc_cost(
    TSGraph::TimeSpaceGraph, bins::Vector{Bin}, src::Int, dst::Int
)::Float64
    dstData, arcData = TSGraph.networkNodes[dst], TSGraph.networkArcs[src, dst]
    # Computing useful quantities
    arcVolume = sum(bin.load for bin in bins; init=0)
    stockCost = sum(stock_cost(bin) for bin in bins; init=0.0)
    # Volume and Stock cost 
    cost = dstData.volumeCost * arcVolume / VOLUME_FACTOR
    cost += arcData.carbonCost * arcVolume / arcData.capacity
    cost += arcData.distance * stockCost
    # Transport cost 
    transportUnits = if arcData.isLinear
        (arcVolume / arcData.capacity)
    else
        ceil(arcVolume / arcData.capacity)
    end
    cost += transportUnits * arcData.unitCost
    return cost
end

function load_plan_design_cost(instance::Instance, solution::Solution)
    totalCost, TSGraph = 0.0, instance.timeSpaceGraph
    # Iterate over sparse matrix
    rows = rowvals(solution.bins)
    vals = nonzeros(solution.bins)
    for j in 1:size(solution.bins, 2)
        for idx in nzrange(solution.bins, j)
            i = rows[idx]
            arcBins = vals[idx]
            # Arc cost
            totalCost += load_plan_design_arc_cost(TSGraph, arcBins, i, j)
        end
    end
    return totalCost
end

function load_plan_design_ils!(solution::Solution, instance::Instance; timeLimit::Int=300)
    bestCost = load_plan_design_cost(instance, solution)
    realCost = compute_cost(instance, solution)
    @info "Starting load plan design ILS" :start_cost = bestCost :real_cost = realCost
    start, i = time(), 0
    while time() - start < timeLimit
        # Perturbating using single plant
        @info "Starting perturbation $i (single_plant)"
        perturbation = get_perturbation(:single_plant, instance, solution)
        is_perturbation_empty(perturbation; verbose=true) && continue
        println("Bundles : $(length(perturbation.bundleIdxs))")
        # With warm start, guaranteed to get a better solution
        pertPaths = solve_lns_milp(instance, perturbation; verbose=true, warmStart=true)
        # If no new paths, end of the search
        !are_new_paths(perturbation.oldPaths, pertPaths; verbose=true) && return nothing
        # Updating solution
        changedIdxs = get_new_paths_idx(perturbation, perturbation.oldPaths, pertPaths)
        bunIdxs = perturbation.bundleIdxs[changedIdxs]
        println("Changed bundles : $(length(bunIdxs))")
        pertBundles = instance.bundles[bunIdxs]
        oldPaths, pertPaths = perturbation.oldPaths[changedIdxs], pertPaths[changedIdxs]
        update_solution!(solution, instance, pertBundles, oldPaths; remove=true)
        update_solution!(solution, instance, pertBundles, pertPaths; sorted=true)
        # Computing cost change 
        newBestCost = load_plan_design_cost(instance, solution)
        newRealCost = compute_cost(instance, solution)
        println(
            "New best cost : $(round(newBestCost; digits=1)) (Real cost : $(round(newRealCost; digits=1)))",
        )
        println(
            "Improvement : $(round(newBestCost - bestCost; digits=1)) (Real improvement : $(round(newRealCost - realCost; digits=1)))",
        )
        bestCost, realCost = newBestCost, newRealCost
        i += 1
    end
end

function load_plan_design_ils2!(solution::Solution, instance::Instance; timeLimit::Int=300)
    bestCost = load_plan_design_cost(instance, solution)
    realCost = compute_cost(instance, solution)
    @info "Starting load plan design ILS" :start_cost = bestCost :real_cost = realCost
    start, i = time(), 0
    while time() - start < timeLimit
        # Perturbating using single plant
        @info "Starting perturbation $i (single_plant)"
        perturbation = get_perturbation(:single_plant, instance, solution)
        is_perturbation_empty(perturbation; verbose=true) && continue
        println("Bundles : $(length(perturbation.bundleIdxs))")
        # With warm start, guaranteed to get a better solution
        pertPaths = solve_lns_milp(
            instance, perturbation; verbose=true, warmStart=true, lowerBoundObj=true
        )
        !are_new_paths(perturbation.oldPaths, pertPaths; verbose=true) && return 0.0, 0
        # Updating solution
        changedIdxs = get_new_paths_idx(perturbation, perturbation.oldPaths, pertPaths)
        bunIdxs = perturbation.bundleIdxs[changedIdxs]
        println("Changed bundles : $(length(bunIdxs))")
        pertBundles = instance.bundles[bunIdxs]
        oldPaths, pertPaths = perturbation.oldPaths[changedIdxs], pertPaths[changedIdxs]
        update_solution!(solution, instance, pertBundles, oldPaths; remove=true)
        update_solution!(solution, instance, pertBundles, pertPaths; sorted=true)
        # Computing cost change 
        newBestCost = load_plan_design_cost(instance, solution)
        newRealCost = compute_cost(instance, solution)
        println(
            "New best cost : $(round(newBestCost; digits=1)) (Real cost : $(round(newRealCost; digits=1)))",
        )
        println(
            "Improvement : $(round(newBestCost - bestCost; digits=1)) (Real improvement : $(round(newRealCost - realCost; digits=1)))",
        )
        bestCost, realCost = newBestCost, newRealCost
        i += 1
    end
end

###########################################################################################
###########################   Split by part Implementation   ##############################
###########################################################################################

# To compute it exaclty, for each bundle groups, they need to choose whether direct or lower bound path which makes it way more easier to solve

function is_direct(arcData::NetworkArc)
    return arcData.type == :direct
end

# Computes the actual lower bound when bundles are split by parts
function split_by_part_lower_bound!(solution::Solution, instance::Instance)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    totCost, lowerBound = 0.0, 0.0
    sort_order_content!(instance)
    # Computing ordinary shortest (direct if possible) and lower bound solution
    @info "Computing base lower bound and shortest delivery"
    lowerBoundSol = Solution(instance)
    lower_bound!(lowerBoundSol, instance)
    # Shortest solution will serve as "new paths" in the attract reduce perturbation, adapted for multiple bundle on direct paths
    shortestSol = Solution(instance)
    shortest_delivery!(shortestSol, instance)
    # Constructing this attract reduce perturbation
    oldPaths = lowerBoundSol.bundlePaths
    newPaths = shortestSol.bundlePaths
    loads = map(bins -> 0, solution.bins)
    perturbation = Perturbation(
        :attract_reduce, idx(instance.bundles), oldPaths, newPaths, loads
    )
    # Constructing the model
    model = model_with_optimizer(; verbose=true)
    @variable(model, z[perturbation.bundleIdxs], Bin)
    arcDatas = TSGraph.networkArcs
    directArcs = [
        (arc.src, arc.dst) for
        arc in edges(TSGraph.graph) if is_direct(arcDatas[arc.src, arc.dst])
    ]
    @variable(model, direct[arc in directArcs], Int)
    @info "MILP has $(num_variables(model)) variables ($(num_binaries(model)) binary and $(num_integers(model)) integer)"

    packConExpr = Dict{Tuple{Int,Int},AffExpr}()
    # Initiating the expressions
    for (src, dst) in directArcs
        packConExpr[(src, dst)] = AffExpr(
            0.0, direct[(src, dst)] => -arcDatas[src, dst].capacity
        )
    end
    # Completing the expressions with the path variables
    for bIdx in perturbation.bundleIdxs
        bundle = instance.bundles[bIdx]
        # Only packing in the direct arc
        if length(newPaths[bIdx]) > 2
            continue
        end
        bSrc, bDst = newPaths[bIdx]
        for order in bundle.orders
            tsSrc, tsDst = time_space_projector(TTGraph, TSGraph, bSrc, bDst, order)
            # Getting the corresponding expression
            packExpr = packConExpr[(tsSrc, tsDst)]
            # Add to expression order.volume * z[bIdx]
            add_to_expression!(packExpr, z[bIdx], order.volume)
        end
    end
    for bIdx in perturbation.bundleIdxs
        bundle = instance.bundles[bIdx]
        # Only packing in the direct arc
        if length(oldPaths[bIdx]) > 2
            continue
        end
        bSrc, bDst = oldPaths[bIdx]
        for order in bundle.orders
            tsSrc, tsDst = time_space_projector(TTGraph, TSGraph, bSrc, bDst, order)
            # Getting the corresponding expression
            packExpr = packConExpr[(tsSrc, tsDst)]
            # Add to expression order.volume * z[bIdx]
            add_to_expression!(packExpr, z[bIdx], order.volume)
        end
    end
    @constraint(model, packing[(src, dst) in directArcs], packConExpr[(src, dst)] <= 0)
    @info "MILP has $(num_constr(model)) constraints"

    # Adapting the objective 
    slope_scaling_cost_update!(TSGraph, Solution(instance))
    objExpr = AffExpr()
    # Adding costs of the common arcs in the time space graph 
    for (src, dst) in directArcs
        add_to_expression!(objExpr, direct[(src, dst)], TSGraph.currentCost[src, dst])
    end
    emptySol = Solution(instance)
    # Adding costs of arcs in the travel time graph
    for bIdx in perturbation.bundleIdxs
        bundle = instance.bundles[bIdx]
        # Adding a cost per path for attract reduce
        oldPathCost = sum(
            arc_lb_update_cost(
                emptySol, TTGraph, TSGraph, bundle, src, dst; current_cost=true
            ) for (src, dst) in partition(perturbation.oldPaths[bIdx], 2, 1)
        )
        # Adding to the objective oldPathCost * (1 - z[bIdx])
        add_to_expression!(objExpr, oldPathCost)
        add_to_expression!(objExpr, z[bIdx], -oldPathCost)
        newPathCost = sum(
            arc_lb_update_cost(
                emptySol, TTGraph, TSGraph, bundle, src, dst; current_cost=true
            ) for (src, dst) in partition(perturbation.oldPaths[bIdx], 2, 1)
        )
        # Adding to the objective newPathCost * z[bIdx]
        add_to_expression!(objExpr, z[bIdx], newPathCost)
    end
    @objective(model, Min, objExpr)
    @info "MILP objective constructed"

    start = time()
    optimize!(model)
    value, bound = JuMP.objective_value(model) + 1e-5, objective_bound(model)
    gap = round(min(100, abs(value - bound) / value); digits=2)
    @info "MILP solved in $(round(time() - start; digits=2)) s with an Objective value = $(round(value; digits=2)) (gap = $gap %)"
    @info "Lower bound computed : $(round(bound; digits=2))"

    bunPaths = get_paths(model, instance, perturbation)
    return update_solution!(solution, instance, instance.bundles, bunPaths; sorted=true)
end

###########################################################################################
###########################   Part Sourcing Optimization   ################################
###########################################################################################

# Creates another instance based on part sourcing optimization
# For every part, 30% (budget) of all quantities can be reallocated to suppliers
# Transport cost based on the lower bound shortest path of one such part from a supplier to a plant 
# We therefore have a integer linear allocation problem with capacities
# Also have to put the constraint that a plant still needs to get the correct amount of said part at the right time

function optimize_part_sourcing(instance::Instance)
    # TODO : think on books and then write here
end