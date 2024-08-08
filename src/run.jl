# Common part of all the heuristic solving process

function get_elapsed_time(startTime::Float64)
    return round((time() - startTime) * 1000) / 1000
end

function run_heuristic(
    instance::Instance,
    heuristic::Function;
    timeLimit::Int=-1,
    preSolve::Bool=true,
    startSol::Solution=Solution(instance),
)
    @info "Running heuristic $heuristic"
    # Initialize start time
    startTime = time()
    # Complete Instance object with all properties needed
    if preSolve
        instance = add_properties(instance, first_fit_decreasing)
        @info "Pre-solve done" :pre_solve_time = get_elapsed_time(startTime)
    end
    # Initialize solution object
    solution = deepcopy(startSol)

    # Run the corresponding heuristic
    heuristic(solution, instance)
    while get_elapsed_time(startTime) < timeLimit
        heuristic(solution, instance)
    end

    solveTime = get_elapsed_time(startTime)
    @info "$heuristic heuristic run with success" :solve_time =
        solveTime, :feasible =
            is_feasible(instance, solution), :total_cost = compute_cost(instance, solution)

    return instance, solution
end

function shortest_delivery_heuristic(instance::Instance)
    return run_heuristic(instance, shortest_delivery!)
end

# Missing slot for average delivery heuristic

function greedy_heuristic(instance::Instance)
    return run_heuristic(instance, greedy!)
end

function lower_bound_heuristic(instance::Instance)
    return run_heuristic(instance, lower_bound!)
end

function local_search_heuristic(instance::Instance, solution::Solution; timeLimit::Int)
    return run_heuristic(
        instance, local_search!; timeLimit=timeLimit, preSolve=false, startSol=solution
    )
end