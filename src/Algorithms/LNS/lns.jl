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
    lowerBoundObj::Bool=false,
)
    # Buidling MILP
    timeLimit = if length(instance.bundles) < 1000
        60.0
    else
        150.0
    end
    model = model_with_optimizer(; verbose=verbose && optVerbose, timeLimit=timeLimit)
    add_variables!(model, instance, perturbation)
    if verbose
        @info "MILP has $(num_variables(model)) variables ($(num_binaries(model)) binary and $(num_integers(model)) integer)"
    end
    add_path_constraints!(model, instance, perturbation)
    add_elementarity_constraints!(model, instance, perturbation)
    add_packing_constraints!(model, instance, perturbation)
    withCuts && add_cut_set_inequalities!(model, instance)
    if verbose
        @info "MILP has $(num_constr(model)) constraints ($(num_path_constr(model)) path, $(num_elem_constr(model)) elementarity, $(num_pack_constr(model)) packing and $(num_cut_constr(model)) cuts)"
    end
    add_objective!(model, instance, perturbation; lowerBound=lowerBoundObj)
    warmStart && warm_start!(model, instance, perturbation)
    # println(model)
    # Solving
    # set_time_limit_sec(model, 300.0)
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

# TODO : in the perturbate loop before the local search, add a mechnism to forbid reperturbating exactly the same way (same plants for single_plants, same arcs for attract_reduces) 

function perturbate!(
    solution::Solution, instance::Instance, neighborhood::Symbol; verbose::Bool=false
)
    verbose && @info "Starting perturbation with neighborhood $neighborhood"

    # Selecting perturbation based on neighborhood given 
    perturbation = get_perturbation(neighborhood, instance, solution)
    is_perturbation_empty(perturbation; verbose=verbose) && return 0.0, 0
    # verbose && println(
    #     "Bundles : $(perturbation.bundleIdxs) \nOld paths : $(perturbation.oldPaths)"
    # )
    verbose && println("Bundles : $(length(perturbation.bundleIdxs))")

    # Computing new paths with lns milp
    pertPaths = solve_lns_milp(instance, perturbation; verbose=verbose, optVerbose=false)
    # verbose && println("New paths : $pertPaths")

    # Filtering bundles to work on
    !are_new_paths(perturbation.oldPaths, pertPaths; verbose=verbose) && return 0.0, 0
    changedIdxs = get_new_paths_idx(perturbation, perturbation.oldPaths, pertPaths)
    bunIdxs = perturbation.bundleIdxs[changedIdxs]
    # verbose && println("Changed bundles : $bunIdxs (changedIdxs = $changedIdxs)")
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
        "Improvement : $(round(improvement; digits=1)) ($(round((improvement / startCost) * 100; digits=1)) %)) (Cost Removed = $(round(costRemoved; digits=1)), Cost Added = $(round(updateCost; digits=1)))",
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
    # println("Update accpeted")
    # return improvement, length(bunIdxs)
end

# How to analyse neighborhood difference with initial solution ? see notes in Books
# We can start with the following mechnism : 
# - try a local search after eahc pertubation 
# - if it can fnd a better solution then keep it
# - if it can't find a better solution, keep the just perturbed solution to appy another perturbation on it 
# - if the three neighborhoods + local search can't find better solution, revert to the solution at the start of the iteration

# TODO : Analyze this mechanism the same way as the other heuristics 

# Config to test :
# - one slope scaling reset at first 
# - slope scaling at each iteration
# - local search after each perturbation

# How to revert the solution to the previous step if the perturbation + local search didn't find a better solution ?
# Put nodes and bundle slection outside of the loop : choose all bundles to be updated with each perturbation before applying them
# Store previous bins for all those bundles at once
# This will also allow for easier miw between neighborhood bundle selection and neighborhood perturbation milp :
# - reduce / attract / two_shared_node / random bundles with single_plant milp could be a good idea

# Combine the large perturbations and the small neighborhoods
# By default small instance time limits for test purposes, but should be used with time limit = 12h = 43200s
# function ILS!(
#     solution::Solution,
#     instance::Instance;
#     timeLimit::Int=1800,
#     perturbTimeLimit::Int=300,
#     lsTimeLimit::Int=300,
#     lsStepTimeLimit::Int=60,
#     resetCost::Bool=false,
#     verbose::Bool=true,
# )
#     startCost = compute_cost(instance, solution)
#     threshold, totImprov, start = 1e-3 * startCost, 0.0, time()
#     println("\n")
#     @info "Starting ILS" :start_cost = startCost :threshold = threshold
#     println("Saving starting solution (in case of too much degradation)")
#     prevSol = solution_deepcopy(solution, instance)
#     # Slope scaling cost update  
#     if resetCost
#         slope_scaling_cost_update!(instance.timeSpaceGraph, Solution(instance))
#     else
#         slope_scaling_cost_update!(instance.timeSpaceGraph, solution)
#     end
#     # Apply perturbations in random order
#     for neighborhood in shuffle(PERTURBATIONS)
#         # Apply perturbation and get correponding solution (1 time for arc flows, multiple time for path flows)
#         perturbStartTime, improvement, changed = time(), 0.0, 0
#         while time() - perturbStartTime < perturbTimeLimit
#             improv, change = perturbate!(solution, instance, neighborhood; verbose=verbose)
#             improvement += improv
#             changed += change
#         end
#         @info "$neighborhood perturbation(s) applied (without local search)" :improvement =
#             improvement :changed = changed
#         # If no path changed, trying one more time the perturbation 
#         if changed == 0
#             @warn "No path changed by $neighborhood perturbation, trying one more time"
#             improv, change = perturbate!(solution, instance, neighborhood; verbose=verbose)
#             improvement += improv
#             changed += change
#             if changed == 0
#                 @warn "No path changed by $neighborhood perturbation, trying another perturbation"
#             end
#         end
#         # Apply local search 
#         improvement += local_search3!(
#             solution, instance; timeLimit=lsTimeLimit, stepTimeLimit=lsStepTimeLimit
#         )
#         totImprov += improvement
#         time() - start > timeLimit && break
#     end
#     println("\n")
#     # Final local search : applying large one
#     lsImprovement = large_local_search!(
#         solution, instance; timeLimit=lsTimeLimit, stepTimeLimit=lsStepTimeLimit
#     )
#     totImprov += lsImprovement
#     @info "Full LNS step done" :time = round(time() - start; digits=2) :improvement = round(
#         totImprov
#     )
#     # Reverting if cost augmented by more than 0.75% (heuristic level)
#     if totImprov > 0.0075 * startCost
#         println("Reverting solution because too much cost degradation")
#         revert_solution!(solution, instance, prevSol)
#         return 0.0
#     else
#         return totImprov
#     end
# end

function ILS!(
    solution::Solution,
    instance::Instance;
    timeLimit::Int=1800,
    perturbTimeLimit::Int=150,
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
        neighborhood = rand(PERTURBATIONS)
        # neighborhood = :single_plant
        # neighborhood = :attract_reduce
        startMilp = time()
        while time() - startMilp < perturbTimeLimit
            improv, change = perturbate!(solution, instance, neighborhood; verbose=verbose)
            @info "$neighborhood perturbation(s) applied (without local search)" :improvement =
                improv :change = change
            changed += change
            # If enough path changed
            if changed >= changeThreshold
                break
            else
                println("Change threshold : $(changed * 100 / changeThreshold)%")
            end
        end
        # Recording step with no change 
        if changed == 0
            noChange += 1
        else
            noChange = 0
        end
        # If enough path changed, next phase
        if changed >= changeThreshold
            # Applying local search 
            local_search3!(
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
            # Applying cost scaling
            slope_scaling_cost_update!(instance, solution)
        end
        # Resetting if multiple times no change
        if noChange == 3
            slope_scaling_cost_update!(instance, Solution(instance))
        end
        # Breaking if multiple times no change
        if noChange >= 5
            break
        end
    end
    println("\n")
    # Final local search : applying large one
    lastSol = solution_deepcopy(bestSol, instance)
    large_local_search!(
        lastSol, instance; timeLimit=lsTimeLimit, stepTimeLimit=lsStepTimeLimit
    )
    if compute_cost(instance, lastSol) < bestCost
        bestSol = solution_deepcopy(lastSol, instance)
        bestCost = compute_cost(instance, lastSol)
        @info "New best solution found" :cost = bestCost :time = round(time() - start)
    end
    totImprov = round(Int, bestCost - startCost)
    @info "Full ILS done" :time = round(time() - start; digits=2) :improvement = totImprov
    # Reverting if cost augmented by more than 0.75% (heuristic level)
    if bestCost > startCost
        println("Reverting solution because cost degradation")
        revert_solution!(solution, instance, prevSol)
        return 0.0
    else
        return totImprov
    end
end

# TODO : create analysis function for the LNS and to decide which architecture should be used 

#######################################################################################
# New idea to be tested
#######################################################################################

# function solve_lns_milp_paths(
#     instance::Instance,
#     solution::Solution,
#     startSol::RelaxedSolution,
#     neighborhood::Symbol,
#     potentialPaths::Vector{Vector{Vector{Int}}};
#     src::Int=-1,
#     dst::Int=-1,
#     warmStart::Bool=true,
#     verbose::Bool=false,
# )
#     # Buidling model
#     model = Model(HiGHS.Optimizer)
#     nPaths = length(potentialPaths[1])
#     add_variables_paths!(model, instance, startSol, nPaths)
#     if verbose
#         nVarBin = count(is_binary, all_variables(model))
#         nVarInt = count(is_integer, all_variables(model))
#         @info "$neighborhood MILP : Added $(num_variables(model)) variables" :binary =
#             nVarBin :integer = nVarInt
#     end
#     add_constraints_paths!(model, instance, solution, startSol, potentialPaths)
#     if verbose
#         nConPath = length(model[:path])
#         nConPack = length(model[:packing])
#         @info "$neighborhood MILP : Added $nConTot constraints" :paths = nConPath :packing =
#             nConPack
#     end
#     add_objective_paths!(model, instance, startSol, potentialPaths)
#     # If warm start option, doing it 
#     # TODO : find a way to activate warm start for two node neighborhood
#     # if warmStart && neighborhood != :two_shared_node
#     #     edgeIndex = create_edge_index(instance.travelTimeGraph)
#     #     warm_start_milp!(model, neighborhood, instance, startSol, edgeIndex)
#     # end
#     # warmStart && warm_start_milp_test(model, instance, startSol)
#     # Solving model
#     set_optimizer_attribute(model, "mip_rel_gap", 0.05)
#     set_time_limit_sec(model, 120.0)
#     # set_silent(model)
#     optimize!(model)
#     # verbose && println(
#     #     "Objective value = $(objective_value(model)) (gap = $(objective_gap(model)))"
#     # )
#     if has_values(model)
#         # Getting the solution paths and returning it
#         return get_paths(model, instance, startSol)
#     else
#         return solution.bundlePaths[startSol.bundleIdxs]
#     end
# end
