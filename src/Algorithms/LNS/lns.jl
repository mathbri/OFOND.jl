# In all heuritisc you will code here, you will have :
# - an instance and some parameters as argument
# - a solution to store the current viable / feasible solution
# - objects, with some constituing the solution, on which you actually work 

# For the attarct reduce neighborhood, switching to multiple paths proposed can be done 
# by adding a binary variable per path and a Special Ordered Set of Type 1 constraint on those, 
# possibly ordered by (real) path cost

# TODO : if elementarity problem in paths returned, add constraint as callback
function solve_lns_milp(
    instance::Instance,
    solution::Solution,
    startSol::RelaxedSolution,
    neighborhood::Symbol;
    src::Int=-1,
    dst::Int=-1,
    warmStart::Bool=true,
    verbose::Bool=false,
)
    # Buidling model
    model = Model(HiGHS.Optimizer)
    add_variables!(model, neighborhood, instance, startSol)
    if verbose
        nVarBin = count(is_binary, all_variables(model))
        nVarInt = count(is_integer, all_variables(model))
        @info "$neighborhood MILP : Added $(num_variables(model)) variables" :binary =
            nVarBin :integer = nVarInt
    end
    add_constraints!(model, neighborhood, instance, solution, startSol, src, dst)
    if verbose
        nConPath = length(model[:path])
        nConOldNew = 0
        if neighborhood == :attract || neighborhood == :reduce
            nConOldNew =
                length(model[:oldPaths]) +
                length(model[:newPaths]) +
                length(model[:forceArcs])
        end
        nConTot = num_constraints(model; count_variable_in_set_constraints=false)
        nConPack = length(model[:packing])
        @info "$neighborhood MILP : Added $nConTot constraints" :paths = nConPath :oldnew =
            nConOldNew :packing = nConPack
    end
    add_objective!(model, instance, startSol)
    # If warm start option, doing it 
    # TODO : find a way to activate warm start for two node neighborhood
    if warmStart && neighborhood != :two_shared_node
        edgeIndex = create_edge_index(instance.travelTimeGraph)
        warm_start_milp!(model, neighborhood, instance, startSol, edgeIndex)
    end
    # warmStart && warm_start_milp_test(model, instance, startSol)
    # Solving model
    set_optimizer_attribute(model, "mip_rel_gap", 0.05)
    set_time_limit_sec(model, 120.0)
    set_silent(model)
    optimize!(model)
    verbose && println(
        "Objective value = $(objective_value(model)) (gap = $(objective_gap(model)))"
    )
    if has_values(model)
        # Getting the solution paths and returning it
        return get_paths(model, instance, startSol)
    else
        return solution.bundlePaths[startSol.bundleIdxs]
    end
end

function solve_lns_milp_paths(
    instance::Instance,
    solution::Solution,
    startSol::RelaxedSolution,
    neighborhood::Symbol,
    potentialPaths::Vector{Vector{Vector{Int}}};
    src::Int=-1,
    dst::Int=-1,
    warmStart::Bool=true,
    verbose::Bool=false,
)
    # Buidling model
    model = Model(HiGHS.Optimizer)
    nPaths = length(potentialPaths[1])
    add_variables_paths!(model, instance, startSol, nPaths)
    if verbose
        nVarBin = count(is_binary, all_variables(model))
        nVarInt = count(is_integer, all_variables(model))
        @info "$neighborhood MILP : Added $(num_variables(model)) variables" :binary =
            nVarBin :integer = nVarInt
    end
    add_constraints_paths!(model, instance, solution, startSol, potentialPaths)
    if verbose
        nConPath = length(model[:path])
        nConPack = length(model[:packing])
        @info "$neighborhood MILP : Added $nConTot constraints" :paths = nConPath :packing =
            nConPack
    end
    add_objective_paths!(model, instance, startSol, potentialPaths)
    # If warm start option, doing it 
    # TODO : find a way to activate warm start for two node neighborhood
    # if warmStart && neighborhood != :two_shared_node
    #     edgeIndex = create_edge_index(instance.travelTimeGraph)
    #     warm_start_milp!(model, neighborhood, instance, startSol, edgeIndex)
    # end
    # warmStart && warm_start_milp_test(model, instance, startSol)
    # Solving model
    set_optimizer_attribute(model, "mip_rel_gap", 0.05)
    set_time_limit_sec(model, 120.0)
    # set_silent(model)
    optimize!(model)
    # verbose && println(
    #     "Objective value = $(objective_value(model)) (gap = $(objective_gap(model)))"
    # )
    if has_values(model)
        # Getting the solution paths and returning it
        return get_paths(model, instance, startSol)
    else
        return solution.bundlePaths[startSol.bundleIdxs]
    end
end

function perturbate!(
    solution::Solution,
    instance::Instance,
    neighborhood::Symbol,
    startCost::Float64,
    costThreshold::Float64;
    verbose::Bool=false,
    inTest::Bool=false,
)::Tuple{Float64,Vector{Int},Vector{Vector{Int}}}
    verbose && println("\nStarting perturbation with neighborhood $neighborhood")

    # Too many nodes and bundles selected lead to not enough improvement possible
    # need to loop all nodes and bundles possible for a type of neighborhood ?

    # Select bundles and node(s) to use depending on the neighborhood chosen
    src, dst, pertBundleIdxs = get_neighborhood_node_and_bundles(
        neighborhood, instance, solution
    )
    if inTest
        while (src, dst) != (17, 15)
            src, dst, pertBundleIdxs = get_neighborhood_node_and_bundles(
                neighborhood, instance, solution
            )
        end
    else
        if neighborhood == :single_plant
            src, dst, pertBundleIdxs = select_random_plant(
                instance, solution, costThreshold
            )
        elseif neighborhood == :two_shared_node
            src, dst, pertBundleIdxs = select_random_two_node(
                instance, solution, costThreshold
            )
        elseif neighborhood == :random
            src, dst, pertBundleIdxs = select_random_bundles(
                instance, solution, costThreshold
            )
        elseif neighborhood == :suppliers
            src, dst, pertBundleIdxs = select_random_suppliers(
                instance, solution, costThreshold
            )
        else
            src, dst, pertBundleIdxs = select_random_common_arc(
                neighborhood, instance, solution, costThreshold
            )
        end
    end
    if neighborhood == :attract && length(pertBundleIdxs) > 0.15 * length(instance.bundles)
        println("Too much bundles taken (>15% of all bundles), capping to 15%")
        MAX_BUNDLES = round(Int, 0.15 * length(instance.bundles))
        pertBundleIdxs = pertBundleIdxs[randperm(length(pertBundleIdxs))[1:MAX_BUNDLES]]
    elseif length(pertBundleIdxs) == 0
        println("No bundles taken, aborting pertubation")
        return 0.011 * startCost, Int[], [Int[]]
    end
    verbose && println("Nodes : $src-$dst, Bundles : $pertBundleIdxs")

    # Filter like local serach to actually compute if there is a chance of good improvement
    pertBundles = instance.bundles[pertBundleIdxs]
    oldPaths = get_lns_paths_to_update(neighborhood, solution, pertBundles, src, dst)
    fullOldPaths = solution.bundlePaths[pertBundleIdxs]
    # verbose && println("Old paths : $oldPaths")

    # The filtering could also occur in terms of cost removed : it must be above a certain threshold
    estimRemCost = sum(
        bundle_estimated_removal_cost(bundle, oldPath, instance, solution) for
        (bundle, oldPath) in zip(pertBundles, oldPaths)
    )
    if estimRemCost <= costThreshold
        verbose && println("Not enough improvement possible, aborting")
        return 0.011 * startCost, Int[], [Int[]]
    end

    # Removing bundle and creating starting solution
    startSol = RelaxedSolution(solution, instance, pertBundles)
    # Putting start sol paths to old paths for two node neighborhood
    if neighborhood == :two_shared_node
        for (i, path) in enumerate(oldPaths)
            startSol.bundlePaths[i] = path
        end
    end

    TSGraph, TTGraph = instance.timeSpaceGraph, instance.travelTimeGraph
    previousBins = save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, pertBundles, oldPaths)
    )
    costRemoved = update_solution!(solution, instance, pertBundles, oldPaths; remove=true)

    # Apply lns milp to get new paths
    # TODO : this line has runtime dispatch
    pertPaths = solve_lns_milp(
        instance,
        solution,
        startSol,
        neighborhood;
        src=src,
        dst=dst,
        verbose=verbose,
        warmStart=false,
    )
    # verbose && println("New paths : $pertPaths")
    if verbose
        changed = count(pertPaths[i] != oldPaths[i] for i in 1:length(oldPaths))
        println("Path changed : ", changed)
    end

    # Update solution (randomized order ?) 
    updateCost = update_solution!(solution, instance, pertBundles, pertPaths; sorted=true)

    # Reverting if cost augmented by more than 0.5% 
    if updateCost + costRemoved > 0.005 * 0.75 * startCost
        verbose && println("Update refused")
        revert_solution!(solution, instance, pertBundles, oldPaths, previousBins, pertPaths)
        return 0.005 * startCost, Int[], [Int[]]
    else
        println("Update accpeted")
        return updateCost + costRemoved, pertBundleIdxs, fullOldPaths
    end
end

# How to analyse neighborhood difference with initial solution ? see notes in Books
# We can start with the following mechnism : 
# - try a local search after eahc pertubation 
# - if it can fnd a better solution then keep it
# - if it can't find a better solution, keep the just perturbed solution to appy another perturbation on it 
# - if the three neighborhoods + local search can't find better solution, revert to the solution at the start of the iteration

# TODO : Analyze this mechanism the same way as the other heuristics 

# TODO : change from highs to gurobi

# TODO : config to test :
# - one slope scaling reset at first 
# - slope scaling at each iteration
# - local search after each perturbation

# TODO : how to revert the solution to the previous step if the perturbation + local search didn't find a better solution ?
# Put nodes and bundle slection outside of the loop : choose all bundles to be updated with each perturbation before applying them
# Store previous bins for all those bundles at once
# This will also allow for easier miw between neighborhood bundle selection and neighborhood perturbation milp :
# - reduce / attract / two_shared_node / random bundles with single_plant milp could be a good idea

# Combine the large perturbations and the small neighborhoods
function LNS!(
    solution::Solution,
    instance::Instance;
    timeLimit::Int=1200,
    lsTimeLimit::Int=300,
    resetCost::Bool=false,
)
    startCost = compute_cost(instance, solution)
    threshold = 3e-3 * startCost
    println("\n")
    @info "Starting LNS step" :start_cost = startCost :threshold = threshold
    totalImprovement = 0.0
    startTime = time()

    # @assert is_feasible(instance, solution)
    println("Saving starting solution")
    prevSol = solution_deepcopy(solution, instance)
    # @assert is_feasible(instance, previousSolution; verbose=true)

    # println("Reverting solution because no improvement was found")
    # revert_solution!(
    #     solution,
    #     instance,
    #     instance.bundles,
    #     previousSolution.bundlePaths,
    #     previousSolution.bins,
    #     solution.bundlePaths,
    # )
    # println("Reverted solution")
    # @assert is_feasible(instance, solution)
    # println("Cost after reverting solution : ", compute_cost(instance, solution))
    # throw(ErrorException("STOP"))

    # Slope scaling cost update  
    if resetCost
        slope_scaling_cost_update!(instance.timeSpaceGraph, Solution(instance))
    else
        slope_scaling_cost_update!(instance.timeSpaceGraph, solution)
    end
    # slope_scaling_cost_update!(instance.timeSpaceGraph, solution)

    # Apply perturbations in random order
    for neighborhood in shuffle(PERTURBATIONS)
        # Apply perturbation and get correponding solution
        improvement, pertBundleIdxs, oldPaths = perturbate!(
            solution, instance, neighborhood, startCost, threshold; verbose=true
        )
        @info "$neighborhood perturbation applied (without local search)" :improvement =
            improvement
        if improvement > 0.005 * 0.75 * startCost
            @info "Cost increased by more than 1% after perturbation, aborting perturbation" :increase =
                improvement / startCost * 100
            # No need to revert, it was already done in perturbate
            continue
        end
        totalImprovement += improvement

        # # Try a local search and if solution better, store with best sol
        # revertBunIdxs = deepcopy(pertBundleIdxs)
        # # TODO : two node incremental makes cost go up, sometimes by a lot, need to investigate
        # # Sometimes also helps so really want to keep just the helping stuff
        # lsStartTime = time()
        # lsImprovement = local_search!(solution, instance; twoNode=true, timeLimit=90)
        # improvement += lsImprovement
        # while (time() - lsStartTime < lsTimeLimit) &&
        #           (time() - startTime < timeLimit) &&
        #           lsImprovement < -1e3
        #     lsImprovement = local_search!(solution, instance; twoNode=false, timeLimit=90)
        #     improvement += lsImprovement
        # end
        # @info "$neighborhood perturbation applied (with local search)" :improvement =
        #     improvement :local_search_improvement = lsImprovement

        # # If no improvement, revert and go to the next perturbation
        # if improvement > -1e-1
        #     @info "Cost increased after perturbation + local search, aborting perturbation" :increase =
        #         improvement / startCost * 100
        #     pertBundles = instance.bundles[revertBunIdxs]
        #     newPaths = solution.bundlePaths[revertBunIdxs]
        #     update_solution!(solution, instance, pertBundles, newPaths; remove=true)
        #     updateCost = update_solution!(
        #         solution, instance, pertBundles, oldPaths; sorted=true
        #     )
        #     # TODO : add warning if too much increase
        # else
        #     # Keeping solution as is and go to the next perturbation
        #     startCost += improvement
        #     totalImprovement += improvement
        #     @info "Improvement found after perturbation + local search" :improvement = round(
        #         improvement
        #     )
        # end

        time() - startTime > timeLimit && break
    end

    println("\n")
    # Final local search
    lsStartTime = time()
    lsImprovement = local_search!(solution, instance; twoNode=true, timeLimit=240)
    totalImprovement += lsImprovement
    while (time() - lsStartTime < lsTimeLimit) &&
              (time() - startTime < timeLimit) &&
              lsImprovement < -1e3
        lsImprovement = local_search!(solution, instance; twoNode=true, timeLimit=240)
        totalImprovement += lsImprovement
    end
    @info "Full LNS step done" :time = round((time() - startTime) * 1000) / 1000 :improvement = round(
        totalImprovement
    )

    if totalImprovement > 0
        println("Reverting solution because no improvement was found")
        @assert is_feasible(instance, prevSol)
        newPaths = deepcopy(solution.bundlePaths)
        revert_solution!(
            solution,
            instance,
            instance.bundles,
            prevSol.bundlePaths,
            prevSol.bins,
            newPaths,
        )
        println("Reverted solution")
        return 0.0
    else
        return totalImprovement
    end
end

# TODO : create analysis function for the LNS and to decide which architecture should be used 