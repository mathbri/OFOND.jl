# In all heuritisc you will code here, you will have :
# - an instance and some parameters as argument
# - a solution to store the current viable / feasible solution
# - objects, with some constituing the solution, on which you actually work 

# TODO : warm start the milp solving with the current solution to gain performance

function single_plant_perturbation!() end

function two_shared_node_perturbation!() end

# TODO : question generating the new paths 
# Maybe make the old one infinitely expensive and compute the new one in a lower bound way to be fast
# Other option is greedy without use_bins
# allow direct for new path ? 
function shared_arc_attract_reduce_perturbation!() end

function solve_lns_milp(
    instance::Instance,
    solution::Solution,
    neighborhood::Symbol,
    bundles::Vector{Bundle};
    src::Int=-1,
    dst::Int=-1,
    newPaths::Vector{Vector{Int}}=Vector{Vector{Int}}(undef, 0),
)
    # Buidling model
    model = Model(HiGHS.Optimizer)
    add_variables!(model, neighborhood, instance, bundles)
    if neighborhood == :single_plant
        add_single_plant_constraints!(model, instance, bundles)
    elseif neighborhood == :two_shared_node
        add_two_node_constraints!(model, instance, bundles, src, dst)
    elseif neighborhood == :attract_reduce
        oldPaths = [solution.bundlePaths[bundle.idx] for bundle in bundles]
        add_attract_reduce_constraints!(model, instance, bundles, oldPaths, newPaths)
    end
    add_objective!(model, neighborhood, bundles)
    # Solving model
    set_optimizer_attribute(model, "mip_rel_gap", 0.05)
    set_optimizer_attribute(model, "time_limit", 120.0)
    set_optimizer_attribute(model, "output_flag", false)
    optimize!(model)
    @assert is_solved_and_feasible(model)
    # Getting the solution paths and returning it
    return get_paths(model, bundles, incidence_matrix(instance.travelTimeGraph.graph))
end

# Common part of all perturbations
function apply_perturbation!()
    # save previous solution state and cost removed
    # construct and solve the correponding milp
    # local search ? If we do it here then saving previous solution make sense, Otherwise do it outside of the function
    # update the solution : revert or update depending on cost

    # select a random plant 
    plant = select_random_plant(instance)
    # get bundles that share the plant
    plantBundles = get_bundles_to_update(solution, plant)
    # apply perturbation 

    # select two nodes of shared network randomly
    src, dst = select_two_nodes(instance.travelTimeGraph)
    # get bundles that share the two nodes
    twoNodeBundles = get_bundles_to_update(instance.bundles, src, dst)
    # apply perturbation 
    # local search ?

    # select an arc of shared network randomly
    # generate new paths
    # apply perturbation
    return nothing
end

# How to analyse neighborhood difference with initial solution ? see notes in Books
# We can start with the following mechnism : 
# - try a local search after eahc pertubation 
# - if it can fnd a better solution then keep it
# - if it can't find a better solution, keep the just perturbed solution to appy another perturbation on it 
# - if the three neighborhoods + local search can't find better solution, revert to the solution at the start of the iteration

# TODO : Analyze this mechanism the same way as the other heuristics 

# Combine the large perturbations and the small neighborhoods
function LNS!(solution::Solution, instance::Instance)
    # Add previous and best solution
    oldSolution, bestSolution = deepcopy(solution), deepcopy(solution)
    # Apply perturbations in random order
    for neighborhood in shuffle(PERTURBATIONS)
        # Apply perturbation and get correponding solution
        # Try a local search and if solution better, store with best sol
        # Go to the next perturbation
    end
    # Final local search
    # Slope scaling cost update  
    return nothing
end

# TODO : create analysis function for the LNS and to decide which architecture should be used 