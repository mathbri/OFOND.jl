# Common part of all the heuristic solving process

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
    totalCost = compute_cost(instance, solution)
    # detect_infeasibility(instance, solution)
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

function lower_bound_heuristic(instance::Instance; parallel::Bool=false)
    if parallel
        return run_heuristic(instance, parallel_lower_bound2!)
    else
        return run_heuristic(instance, lower_bound!)
    end
end

function lower_bound_filtering_heuristic(instance::Instance; parallel::Bool=false)
    if parallel
        run_heuristic(instance, parallel_lower_bound_filtering2!)
    else
        run_heuristic(instance, lower_bound_filtering!)
    end
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
    # Applying local search at least once
    improvement, lsLoops = 1.0, 0
    while (get_elapsed_time(startTime) < timeLimit || lsLoops < 1) && improvement > 1e-3
        improvement = local_search!(solution, instance; timeLimit=timeLimit, twoNode=true)
    end
    # If local search stops because of time limit, applying bundle reintroduction one last time 
    if get_elapsed_time(startTime) > timeLimit && improvement < -1e3
        improvement = local_search!(solution, instance; timeLimit=timeLimit)
    end

    solveTime = get_elapsed_time(startTime)
    feasible = is_feasible(instance, solution)
    totalCost = compute_cost(instance, solution)
    # detect_infeasibility(instance, solution)
    @info "Final results" :solve_time = solveTime :feasible = feasible :total_cost =
        return instance, solution
end

function local_search_heuristic!(
    solution::Solution, instance::Instance; timeLimit::Int, stepLimit::Int=120
)
    println()
    improvThreshold = -5e-4 * compute_cost(instance, solution)
    @info "Running Local Search heuristic" :min_improvement = improvThreshold
    # Initialize start time
    startTime = time()

    improvement = local_search!(solution, instance; timeLimit=stepLimit)
    while get_elapsed_time(startTime) < timeLimit && improvement < improvThreshold
        improvement = local_search!(solution, instance; timeLimit=stepLimit)
    end
    local_search!(solution, instance; timeLimit=stepLimit)

    solveTime = get_elapsed_time(startTime)
    feasible = is_feasible(instance, solution)
    solCost = compute_cost(instance, solution)
    # detect_infeasibility(instance, solution)
    println()
    @info "Final results" :solve_time = solveTime :feasible = feasible :total_cost = solCost
    return println()
end

# TODO : add mechanism to restart from a completely diffreent solution

function lns_heuristic!(
    solution::Solution,
    instance::Instance;
    timeLimit::Int,
    lsTimeLimit::Int,
    lsStepTimeLimit::Int,
)
    improvThreshold = -1e-4 * compute_cost(instance, solution)
    bestSol = solution_deepcopy(solution, instance)
    @info "Running Large Neighborhood Search heuristic" :min_improvement = improvThreshold
    # Initialize start time
    startTime = time()

    improvement = LNS!(
        solution, instance; timeLimit=timeLimit, lsTimeLimit=lsTimeLimit, resetCost=true
    )
    unfruitful = 0
    resetCost = false
    while get_elapsed_time(startTime) < timeLimit
        if unfruitful == 1
            resetCost = true
        elseif unfruitful == 3
            break
            # We are restarting so we need to store the best solution found so far
            bestSol = solution_deepcopy(solution, instance)
            # TODO : restart with greedy and random insertion order
        end
        improvement = LNS!(solution, instance; timeLimit=timeLimit, lsTimeLimit=lsTimeLimit)
        if improvement > improvThreshold
            unfruitful += 1
        else
            unfruitful = 0
        end
    end

    solveTime = get_elapsed_time(startTime)
    feasible = is_feasible(instance, solution)
    solCost = compute_cost(instance, solution)
    # detect_infeasibility(instance, solution)
    println()
    @info "Final results" :solve_time = solveTime :feasible = feasible :total_cost = solCost
    return println()
end