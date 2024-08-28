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
        CAPACITIES = Int[]
        instance = add_properties(instance, tentative_first_fit, CAPACITIES)
        @info "Pre-solve done" :pre_solve_time = get_elapsed_time(startTime)
    end
    # Initialize solution object
    solution = if Base.size(startSol.bins) != (0, 0)
        deepcopy(startSol)
    else
        Solution(instance)
    end

    # Run the corresponding heuristic
    heuristic(solution, instance)
    println("Cost after initial heuristic: $(compute_cost(instance, solution))")
    improvement = 1.0
    while get_elapsed_time(startTime) < timeLimit && improvement > 1e-3
        improvement = heuristic(solution, instance)
    end

    solveTime = get_elapsed_time(startTime)
    feasible = is_feasible(instance, solution)
    # detect_infeasibility(instance, solution)
    @info "$heuristic heuristic results" :solve_time = solveTime :feasible = feasible :total_cost =
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

function lower_bound_filtering_heuristic(instance::Instance)
    return run_heuristic(instance, lower_bound_filtering!)
end

function local_search_heuristic(instance::Instance, solution::Solution; timeLimit::Int)
    return run_heuristic(
        instance, local_search!; timeLimit=timeLimit, preSolve=false, startSol=solution
    )
end

function greedy_than_ls!(solution::Solution, instance::Instance)
    # If the solution is empty, apply greedy heuristic
    randomIdx = rand(1:length(instance.bundles))
    if solution.bundlePaths[randomIdx] == [-1, -1]
        greedy!(solution, instance)
    else
        # If the solution is not empty, apply local search heuristic
        local_search!(solution, instance)
    end
end

function greedy_then_ls_heuristic(instance::Instance; timeLimit::Int)
    return run_heuristic(instance, greedy_than_ls!; timeLimit=timeLimit)
end

function greedy_or_lb_then_ls_heuristic(instance::Instance; timeLimit::Int=-1)
    @info "Running heuristic greedy_or_lb_tan_ls!"
    # Initialize start time
    startTime = time()
    # Complete Instance object with all properties needed

    CAPACITIES = Int[]
    instance = add_properties(instance, tentative_first_fit, CAPACITIES)
    @info "Pre-solve done" :pre_solve_time = get_elapsed_time(startTime)

    # Initialize solution object
    solution1 = Solution(instance)
    solution2 = Solution(instance)

    # Run the corresponding heuristic
    greedyCost = greedy!(solution1, instance)
    println("Cost after greedy heuristic: $(compute_cost(instance, solution1))")
    lower_bound!(solution2, instance)
    lbCost = compute_cost(instance, solution2)
    println("Cost after lower bound heuristic: $(lbCost)")

    # Choosing the best initial solution on which to apply local search 
    solution = solution1
    if lbCost < greedyCost
        solution = solution2
        @info "Choosing lower bound solution as initial solution"
    else
        @info "Choosing greedy solution as initial solution"
    end
    improvement = 1.0
    while get_elapsed_time(startTime) < timeLimit && improvement > 1e-3
        improvement = local_search!(solution, instance; timeLimit=timeLimit, twoNode=true)
    end

    solveTime = get_elapsed_time(startTime)
    feasible = is_feasible(instance, solution)
    # detect_infeasibility(instance, solution)
    @info "Final results" :solve_time = solveTime :feasible = feasible :total_cost =
        return instance, solution
end

function local_search_heuristic!(solution::Solution, instance::Instance; timeLimit::Int)
    @info "Running Local Search heuristic"
    # Initialize start time
    startTime = time()

    improvement = local_search!(solution, instance; timeLimit=timeLimit, twoNode=true)
    while get_elapsed_time(startTime) < timeLimit && improvement > 1
        improvement = local_search!(solution, instance; timeLimit=timeLimit, twoNode=true)
    end

    solveTime = get_elapsed_time(startTime)
    feasible = is_feasible(instance, solution)
    solCost = compute_cost(instance, solution)
    # detect_infeasibility(instance, solution)
    println()
    @info "Final results" :solve_time = solveTime :feasible = feasible :total_cost = solCost
    return println()
end

function lns_heuristic!(solution::Solution, instance::Instance; timeLimit::Int)
    @info "Running Large Neighborhood Search heuristic"
    # Initialize start time
    startTime = time()

    # TODO : add a mechanism to periodically reset costs ?
    improvement = LNS!(solution, instance; timeLimit=timeLimit, resetCost=true)
    while get_elapsed_time(startTime) < timeLimit && improvement > 1
        improvement = LNS!(solution, instance; timeLimit=timeLimit)
    end

    solveTime = get_elapsed_time(startTime)
    feasible = is_feasible(instance, solution)
    solCost = compute_cost(instance, solution)
    # detect_infeasibility(instance, solution)
    println()
    @info "Final results" :solve_time = solveTime :feasible = feasible :total_cost = solCost
    return println()
end