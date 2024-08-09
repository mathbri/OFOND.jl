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
        instance = add_properties(instance, tentative_first_fit)
        @info "Pre-solve done" :pre_solve_time = get_elapsed_time(startTime)
    end
    # Initialize solution object
    solution = if Base.size(startSol.bins) != (0, 0)
        deepcopy(startSol)
    else
        Solution(instance)
    end

    println(solution.bundlePaths)
    println(solution.bins[1, 1])

    # Run the corresponding heuristic
    heuristic(solution, instance)
    while get_elapsed_time(startTime) < timeLimit
        heuristic(solution, instance)
    end

    println(solution.bundlePaths)
    println(solution.bins[1, 1])

    solveTime = get_elapsed_time(startTime)
    feasible = is_feasible(instance, solution)
    totalCost = compute_cost(instance, solution)
    @info "$heuristic heuristic results" :solve_time = solveTime :feasible = feasible :total_cost =
        totalCost

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