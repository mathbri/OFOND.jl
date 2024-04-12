# Common part of all the heuristic solving process
function run_heuristic(instance::Instance, heuristic::Function)
    # Initialize start time
    startTime = time()
    # Complete Instance object with all properties needed
    instance = add_properties(instance, first_fit_decreasing)
    # Initialize solution object
    solution = Solution(instance)

    # Saving pre-solve time
    preSolveTime = round((time() - startTime) * 1000) / 1000
    println("Pre-solve time : $preSolveTime s")

    # Run the corresponding heuristic
    heuristic(instance, solution)

    # Saving solve time
    solveTime = round((time() - preSolveTime) * 1000) / 1000
    println("solve time : $solveTime s")
    println("Feasible : $(is_feasible(instance, solution))")
    println("Total Cost : $(compute_cost(solution))")

    return instance, solution
end