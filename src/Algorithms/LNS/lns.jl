# For the attarct reduce neighborhood, switching to multiple paths proposed can be done 
# by adding a binary variable per path and a Special Ordered Set of Type 1 constraint on those, 
# possibly ordered by (real) path cost

function solve_lns_milp(
    instance::Instance,
    perturbation::Perturbation;
    warmStart::Bool=false,
    verbose::Bool=false,
    optVerbose::Bool=false,
    withCuts::Bool=false,
)
    # Buidling MILP
    model = model_with_optimizer(; verbose=verbose && optVerbose)
    add_variables!(model, instance, perturbation)
    if verbose
        @info "MILP has $(num_variables(model)) variables ($(num_binaries(model)) binary and $(num_integers(model)) integer)"
    end
    add_path_constraints!(model, instance, perturbation)
    add_packing_constraints!(model, instance, perturbation)
    if verbose
        @info "MILP has $(num_constr(model)) constraints ($(num_path_constr(model)) path, $(num_pack_constr(model)) packing and $(num_cut_constr(model)) cuts)"
    end
    add_objective!(model, instance, perturbation)
    warmStart && warm_start!(model, instance, perturbation)

    start = time()
    optimize!(model)

    # Getting the solution 
    if has_values(model)
        if verbose
            # Can cause conflict with InferOpt objective_value
            value, bound = JuMP.objective_value(model) + 1e-5, objective_bound(model)
            gap = round(min(100, abs(value - bound) / value); digits=2)
            @info "MILP solved in $(round(time() - start; digits=2)) s with an Objective value = $(round(value; digits=2)) (gap = $gap %)"
        end
        return get_paths(model, instance, perturbation)
    else
        @info "MILP found no solution in $(round(time() - start; digits=2)) s"
        return perturbation.oldPaths
    end
end

function perturbate!(
    solution::Solution, instance::Instance, neighborhood::Symbol; verbose::Bool=false
)
    verbose && @info "Starting perturbation with neighborhood $neighborhood"

    # Selecting perturbation based on neighborhood given 
    perturbation = get_perturbation(neighborhood, instance, solution)
    is_perturbation_empty(perturbation; verbose=verbose) && return 0.0, 0
    verbose && println("Bundles : $(length(perturbation.bundleIdxs))")

    # Computing new paths with lns milp
    pertPaths = solve_lns_milp(instance, perturbation; verbose=verbose, optVerbose=true)

    # Filtering bundles to work on
    !are_new_paths(perturbation.oldPaths, pertPaths; verbose=verbose) && return 0.0, 0
    changedIdxs = get_new_paths_idx(perturbation, perturbation.oldPaths, pertPaths)
    bunIdxs = perturbation.bundleIdxs[changedIdxs]
    verbose && println("Changed bundles : $(length(bunIdxs))")

    pertBundles = instance.bundles[bunIdxs]
    # Here we want to have changedIdxs not bunIdxs
    oldPaths, pertPaths = perturbation.oldPaths[changedIdxs], pertPaths[changedIdxs]

    # Applying new paths to the bundles for which it actually changed
    startCost = compute_cost(instance, solution)
    previousBins = save_previous_bins(instance, solution, pertBundles, oldPaths)
    costRemoved = update_solution!(solution, instance, pertBundles, oldPaths; remove=true)
    updateCost = update_solution!(solution, instance, pertBundles, pertPaths; sorted=true)
    improvement = updateCost + costRemoved
    verbose && println(
        "Improvement : $(round(improvement; digits=1)) (Cost Removed = $(round(costRemoved; digits=1)), Cost Added = $(round(updateCost; digits=1)))",
    )

    # Reverting if cost augmented by more than 5% 
    if updateCost + costRemoved > 0.05 * startCost
        verbose && println("Update refused")
        revert_solution!(solution, instance, pertBundles, oldPaths, previousBins, pertPaths)
        return 0.0, 0
    else
        verbose && println("Update accpeted")
        return improvement, length(bunIdxs)
    end
end

# Combine the large perturbations and the small neighborhoods
# By default small instance time limits for test purposes, but should be used with time limit = 12h = 43200s
function ILS!(
    solution::Solution,
    instance::Instance;
    timeLimit::Int=1800,
    perturbTimeLimit::Int=300,
    lsTimeLimit::Int=300,
    lsStepTimeLimit::Int=60,
    resetCost::Bool=false,
    verbose::Bool=true,
)
    startCost = compute_cost(instance, solution)
    threshold, totImprov, start = 1e-3 * startCost, 0.0, time()
    println("\n")
    @info "Starting ILS" :start_cost = startCost :threshold = threshold

    bestSol = solution_deepcopy(solution, instance)
    bestCost = startCost
    # Slope scaling cost update
    if resetCost
        slope_scaling_cost_update!(instance.timeSpaceGraph, Solution(instance))
    else
        slope_scaling_cost_update!(instance.timeSpaceGraph, solution)
    end
    # Apply perturbations in random order
    changed, noChange = 0, 0
    changeThreshold = 0.1 * length(instance.bundles)
    while time() - start < timeLimit
        # neighborhood = rand(PERTURBATIONS)
        neighborhood = :single_plant
        improv, change = perturbate!(solution, instance, neighborhood; verbose=verbose)
        @info "$neighborhood perturbation(s) applied (without local search)" :improvement =
            improv :change = change
        changed += change
        # If enough path changed, applying local search 
        if changed >= changeThreshold
            local_search!(
                solution, instance; timeLimit=lsTimeLimit, stepTimeLimit=lsStepTimeLimit
            )
            changed = 0
            # If new best solution found, store it
            if compute_cost(instance, solution) < bestCost
                bestSol = solution_deepcopy(solution, instance)
                bestCost = compute_cost(instance, solution)
                @info "New best solution found" :cost = bestCost :time = round(
                    time() - start
                )
            end
        else
            println("Change threshold : $(change * 100 / changeThreshold)%")
        end
        # Recording step with no change 
        if change == 0
            noChange += 1
        else
            noChange = 0
        end
        # Breaking if multiple times no change
        if noChange >= 5
            break
        end
    end
    println("\n")
    # Final local search : applying large one
    lsImprovement = large_local_search!(
        bestSol, instance; timeLimit=lsTimeLimit, stepTimeLimit=lsStepTimeLimit
    )
    finalCost = compute_cost(instance, bestSol)
    totImprov = finalCost - startCost
    relImprov = round(totImprov / startCost * 100; digits=2)
    timeTaken = round(time() - start; digits=2)
    @info "Full ILS done" :time = timeTaken :improvement = totImprov :relative_improvement =
        relImprov
    # Reverting if cost augmented by more than 0.75% (heuristic level)
    if totImprov > 0.0075 * startCost
        println("Reverting solution because too much cost degradation")
        revert_solution!(solution, instance, prevSol)
        return 0.0
    else
        return totImprov
    end
end
