# Common part of all the heuristic solving process

function get_elapsed_time(startTime::Float64)
    return round((time() - startTime) * 1000) / 1000
end

function run_heuristic(instance::Instance, heuristic::Function; timeLimit::Int=-1)
    # Initialize start time
    startTime = time()
    # Complete Instance object with all properties needed
    instance = add_properties(instance, first_fit_decreasing)
    # Initialize solution object
    solution = Solution(instance)

    # Saving pre-solve time
    preSolveTime = get_elapsed_time(startTime)
    println("Pre-solve time : $(preSolveTime) s")

    # Run the corresponding heuristic
    heuristic(solution, instance, timeLimit)
    while get_elapsed_time(preSolveTime) < timeLimit
        heuristic(solution, instance, timeLimit)
    end

    # Saving solve time
    solveTime = get_elapsed_time(preSolveTime)
    println("Solve time : $solveTime s")
    println("Feasible : $(is_feasible(instance, solution))")
    println("Total Cost : $(compute_cost(instance, solution))")

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

function local_search_heuristic(instance::Instance, timeLimit::Int)
    return run_heuristic(instance, local_search!; timeLimit=timeLimit)
end