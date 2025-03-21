# File used to launch all kinds of scripts using OFOND package 

# using OFOND
using ProfileView
using JLD2
using Statistics

function julia_main(; useILS::Bool, splitBundles::Bool, useWeights::Bool)::Cint
    # Read files based on ARGS
    println("Launching OFO Network Design")
    println("Arguments : ", ARGS)
    directory = joinpath(Base.dirname(@__DIR__), "scripts", "data_test")
    if length(ARGS) >= 1
        if isdir(ARGS[1])
            directory = ARGS[1]
        else
            @warn "First argument (data directory) is not a directory, switching to default" :directory_given = ARGS[1] :default =
                directory
        end
    end
    # length(ARGS) >= 1 && isdir(ARGS[1]) && (directory = ARGS[1])
    println("Reading data from $directory")
    node_file = joinpath(directory, "ND-MD-Geo_V5_preprocessing 1.csv")
    if length(ARGS) >= 2
        node_file_given = joinpath(directory, ARGS[2])
        if isfile(node_file_given)
            node_file = node_file_given
        else
            @warn "Second argument (node file) is not a file (or doesn't exist), switching to default" :file_given =
                node_file_given :default = node_file
        end
    end
    # length(ARGS) >= 2 && isfile(ARGS[2]) && (node_file = ARGS[2])
    leg_file = joinpath(directory, "Legs_preprocessed 1.csv")
    if length(ARGS) >= 3
        leg_file_given = joinpath(directory, ARGS[3])
        if isfile(leg_file_given)
            leg_file = leg_file_given
        else
            @warn "Third argument (leg file) is not a file (or doesn't exist), switching to default" :file_given =
                leg_file_given :default = leg_file
        end
    end
    # length(ARGS) >= 3 && isfile(ARGS[3]) && (leg_file = ARGS[3])
    com_file = joinpath(directory, "Volumes_preprocessed 1.csv")
    if length(ARGS) >= 4
        com_file_given = joinpath(directory, ARGS[4])
        if isfile(com_file_given)
            com_file = com_file_given
        else
            @warn "Fourth argument (commodity file) is not a file (or doesn't exist), switching to default" :file_given =
                com_file_given :default = com_file
        end
    end
    # length(ARGS) >= 4 && isfile(ARGS[4]) && (com_file = ARGS[4])
    # read instance 
    instance = read_instance(node_file, leg_file, com_file)
    # println("Instance dates : $(instance.dates)")

    # adding properties to the instance
    CAPACITIES = Int[]
    instance = add_properties(instance, tentative_first_fit, CAPACITIES)

    # read solution
    sol_file = joinpath(directory, "route_Preprocessed 1.csv")
    if length(ARGS) >= 5
        sol_file_given = joinpath(directory, ARGS[5])
        if isfile(sol_file_given)
            sol_file = sol_file_given
        else
            @warn "Fifth argument (solution file) is not a file (or doesn't exist), switching to default" :file_given =
                sol_file_given :default = sol_file
        end
    end
    # length(ARGS) >= 5 && isfile(ARGS[5]) && (sol_file = ARGS[5])
    solution = read_solution(instance, sol_file)

    # Export directory
    exportDir = joinpath(dirname(@__DIR__), "scripts", "export")
    if length(ARGS) >= 6
        if isdir(ARGS[6])
            exportDir = ARGS[6]
        else
            @warn "Sixth argument (export directory) is not a directory, switching to default" :directory_given = ARGS[6] :default =
                exportDir
        end
    end

    println("Exporting current solution to $exportDir")
    write_solution(solution, instance; suffix="current", directory=exportDir)

    # Filtering procedure 
    _, solution_LBF = lower_bound_filtering_heuristic(instance)
    println(
        "Bundles actually filtered : $(count(x -> length(x) == 2, solution_LBF.bundlePaths))",
    )
    instanceSub = extract_filtered_instance(instance, solution_LBF)
    instanceSub = add_properties(instanceSub, tentative_first_fit, CAPACITIES)

    # Greedy or Lower Bound than Local Search heuristic
    _, solutionSub_GLS = greedy_or_lb_then_ls_heuristic(instanceSub; timeLimit=300)

    # Fusing solutions
    finalSolution = fuse_solutions(solutionSub_GLS, solution_LBF, instance, instanceSub)

    # Cleaning final solution linears arcs
    @info "Cleaning final solution before extraction"
    bin_packing_improvement!(finalSolution, instance; sorted=true, skipLinear=false)
    clean_empty_bins!(finalSolution, instance)

    # length(ARGS) >= 6 && isdir(directory) && (directory = ARGS[6])
    println("Exporting proposed solution to $exportDir")
    write_solution(finalSolution, instance; suffix="proposed", directory=exportDir)

    return 0 # if things finished successfully
end

function julia_main_test()
    println("Launching OFO Network Design (test)")

    directory = joinpath(Base.dirname(@__DIR__), "scripts", "data_test")
    println("Reading data from $directory")
    node_file = joinpath(directory, "ND-MD-Geo_V5_preprocessing.csv")
    leg_file = joinpath(directory, "Legs_preprocessed.csv")
    com_file = joinpath(directory, "Volumes_preprocessed.csv")
    # read instance 
    instance = read_instance(node_file, leg_file, com_file)
    # adding properties to the instance
    CAPACITIES = Int[]
    instance = add_properties(instance, tentative_first_fit, CAPACITIES)
    # read solution
    sol_file = joinpath(directory, "route_Preprocessed.csv")
    solution = read_solution(instance, joinpath(directory, sol_file))

    # cut it into smaller instances 
    instanceSub = instance
    # instanceSub = split_all_bundles_by_part(instanceSub)
    # instanceSub = split_all_bundles_by_time(instanceSub, 4)

    @info "Filtering with lower bound"
    _, solution_LBF = lower_bound_heuristic(instanceSub)
    println("Bundles filtered : $(count(x -> length(x) == 2, solution_LBF.bundlePaths))")
    instanceSubSub = extract_filtered_instance(instanceSub, solution_LBF)
    instanceSubSub = add_properties(instanceSubSub, tentative_first_fit, CAPACITIES)

    @info "Finishing load plan design construction"
    solution_MILP = Solution(instanceSubSub)
    plant_by_plant_milp!(solution_MILP, instanceSubSub)
    feasible = is_feasible(instanceSubSub, solution_MILP)
    totalCost = compute_cost(instanceSubSub, solution_MILP)
    @info "Load plan design heuristic results" :feasible = feasible :total_cost = totalCost

    load_plan_design_ils!(solution_MILP, instanceSubSub; timeLimit=300)
    feasible = is_feasible(instanceSubSub, solution_MILP)
    totalCost = compute_cost(instanceSubSub, solution_MILP)
    @info "Load plan design ILS results" :feasible = feasible :total_cost = totalCost

    # return 0

    @info "Filtering with standard procedure"
    _, solution_LBF = lower_bound_filtering_heuristic(instanceSub)
    println("Bundles filtered : $(count(x -> length(x) == 2, solution_LBF.bundlePaths))")

    instanceSubSub = extract_filtered_instance(instanceSub, solution_LBF)
    instanceSubSub = add_properties(instanceSubSub, tentative_first_fit, CAPACITIES)

    nCom = sum(b -> sum(o -> length(o.content), b.orders), instanceSubSub.bundles)
    meanSize =
        sum(b -> sum(o -> sum(c -> c.size, o.content), b.orders), instanceSubSub.bundles) /
        nCom / VOLUME_FACTOR
    meanCost =
        sum(
            b -> sum(o -> sum(c -> c.stockCost, o.content), b.orders),
            instanceSubSub.bundles,
        ) / nCom
    println("Mean size $meanSize and mean cost $meanCost")

    @info "Constructing greedy, lower bound and mixed solution"
    solution_Mix = Solution(instanceSubSub)
    solution_G, solution_LB = mix_greedy_and_lower_bound!(solution_Mix, instanceSubSub)
    feasibles = [
        is_feasible(instanceSubSub, sol) for sol in [solution_Mix, solution_G, solution_LB]
    ]
    mixCost = compute_cost(instanceSubSub, solution_Mix)
    gCost = compute_cost(instanceSubSub, solution_G)
    lbCost = compute_cost(instanceSubSub, solution_LB)
    @info "Mixed heuristic results" :feasible = feasibles :mixed_cost = mixCost :greedy_cost =
        gCost :lower_bound_cost = lbCost

    # Choosing the best solution as the starting solution
    solutionSub = solution_G
    choiceSolution = argmin([mixCost, gCost, lbCost])
    if choiceSolution == 3
        solutionSub = solution_LB
        @info "Lower bound solution chosen"
    elseif choiceSolution == 1
        solutionSub = solution_Mix
        @info "Mixed solution chosen"
    else
        @info "Greedy solution chosen"
    end

    # Applying local search 
    local_search3!(solutionSub, instanceSubSub)

    # Applying ILS 
    LNS2!(solutionSub, instanceSubSub)

    return 0

    # _, solutionSub_LB = lower_bound_heuristic(instanceSubSub)

    # solutionSub_LNS = LNS2(solutionSub_LB, instanceSubSub)

    # _, solutionSub_G = greedy_heuristic(instanceSubSub)

    @info "Running heuristic average delivery"
    startTime = time()
    solution = Solution(instanceSubSub)
    average_delivery!(solution, instanceSubSub)
    println("Cost after heuristic: $(compute_cost(instanceSubSub, solution))")
    solveTime = get_elapsed_time(startTime)
    feasible = is_feasible(instanceSubSub, solution)
    totalCost = compute_cost(instanceSubSub, solution)
    @info "Results" :solve_time = solveTime :feasible = feasible :total_cost = totalCost

    @info "Running heuristic fully outsourced"
    startTime = time()
    solution = Solution(instanceSubSub)
    fully_outsourced2!(solution, instanceSubSub)
    println("Cost after heuristic: $(compute_cost(instanceSubSub, solution))")
    solveTime = get_elapsed_time(startTime)
    feasible = is_feasible(instanceSubSub, solution)
    totalCost = compute_cost(instanceSubSub, solution)
    @info "Results" :solve_time = solveTime :feasible = feasible :total_cost = totalCost

    local_search3!(solutionSub_LB, instanceSubSub)

    # sol = LNS2(solutionSub_LB, instanceSubSub)

    return 0

    directory = joinpath(Base.dirname(@__DIR__), "scripts", "data_test")
    println("Reading data from $directory")
    node_file = joinpath(directory, "ND-MD-Geo_V5_preprocessing.csv")
    leg_file = joinpath(directory, "Legs_preprocessed.csv")
    com_file = joinpath(directory, "Volumes_preprocessed.csv")
    # read instance 
    instance = read_instance(node_file, leg_file, com_file)
    # adding properties to the instance
    CAPACITIES = Int[]
    instance = add_properties(instance, tentative_first_fit, CAPACITIES)
    # read solution
    sol_file = joinpath(directory, "route_Preprocessed.csv")
    solution = read_solution(instance, joinpath(directory, sol_file))

    # cut it into smaller instances 
    instanceSub = instance
    # instanceSub = extract_sub_instance(instance; country="FRANCE", timeHorizon=6)
    # instanceSub = extract_sub_instance2(
    #     instance;
    #     continents=["Western Europe", "South America", "South-East Asia"],
    #     timeHorizon=6,
    # )

    # instanceSub = split_all_bundles_by_part(instanceSub)
    instanceSub = split_all_bundles_by_time(instanceSub, 4)

    # adding properties to the instance
    # instanceSub = add_properties(instanceSub, tentative_first_fit, CAPACITIES)
    # solutionSub_C = extract_sub_solution(solution, instance, instanceSub)
    # solutionSub_C = solution

    # test algorithms  

    _, solution_LBF = lower_bound_filtering_heuristic(instanceSub)
    println(
        "Bundles actually filtered : $(count(x -> length(x) == 2, solution_LBF.bundlePaths))",
    )

    # return 0

    # _, solution_LBF2 = lower_bound_filtering_heuristic(instance; parallel=true)
    # println(
    #     "Bundles actually filtered : $(count(x -> length(x) == 2, solution_LBF2.bundlePaths))",
    # )

    instanceSubSub = extract_filtered_instance(instanceSub, solution_LBF)
    instanceSubSub = add_properties(instanceSubSub, tentative_first_fit, CAPACITIES)

    # solutionSub_C = extract_sub_solution(solution, instance, instanceSubSub)
    # solutionSub_C = solution

    save("instance.jld2", "instance", instanceSubSub)

    netGraph = instanceSubSub.networkGraph.graph
    nSuppliers = count(lab -> netGraph[lab].type == :supplier, labels(netGraph))
    nPlants = count(lab -> netGraph[lab].type == :plant, labels(netGraph))
    println("$nSuppliers suppliers and $nPlants plants")

    nPlat = length(labels(netGraph)) - nSuppliers - nPlants
    meanPlatCost = sum(lab -> netGraph[lab].volumeCost, labels(netGraph)) / nPlat
    nCom = sum(b -> sum(o -> length(o.content), b.orders), instanceSubSub.bundles)
    meanSize =
        sum(b -> sum(o -> sum(c -> c.size, o.content), b.orders), instanceSubSub.bundles) /
        nCom / VOLUME_FACTOR
    meanCost =
        sum(
            b -> sum(o -> sum(c -> c.stockCost, o.content), b.orders),
            instanceSubSub.bundles,
        ) / nCom
    println(
        "Mean platform cost $meanPlatCost and mean size $meanSize and mean cost $meanCost"
    )
    allTransCost = sum(a -> netGraph[a[1], a[2]].unitCost, edge_labels(netGraph))
    allCarbCost = sum(a -> netGraph[a[1], a[2]].carbonCost, edge_labels(netGraph))
    println("Share of transportation cost $(allTransCost / (allTransCost + allCarbCost))")

    # printing bundle arcs to see difference
    println(
        "Min bundle arcs : $(minimum(x -> length(x), instanceSubSub.travelTimeGraph.bundleArcs))",
    )
    println(
        "Mean bundle arcs : $(mean(x -> length(x), instanceSubSub.travelTimeGraph.bundleArcs))",
    )
    println(
        "Max bundle arcs : $(maximum(x -> length(x), instanceSubSub.travelTimeGraph.bundleArcs))",
    )

    # return 0
    # end

    # function julia_main_test2()
    # println("Loading instance")
    # instanceSubSub = load("instance.jld2", "instance")

    # _, solutionSub_SD = shortest_delivery_heuristic(instanceSub)
    # global MAX_LENGTH, GREEDY_RECOMPUTATION = 0, 0

    # _, solutionSub_G = greedy_heuristic(instanceSubSub)
    # greedyCost = compute_cost(instanceSubSub, solutionSub_G)

    # @info "Running heuristic greedy with mode 2"
    # startTime = time()
    # solution = Solution(instanceSubSub)
    # greedy!(solution, instanceSubSub; mode=2)
    # println("Cost after heuristic: $(compute_cost(instanceSubSub, solution))")
    # solveTime = get_elapsed_time(startTime)
    # feasible = is_feasible(instanceSubSub, solution)
    # totalCost = compute_cost(instanceSubSub, solution)
    # @info "Results" :solve_time = solveTime :feasible = feasible :total_cost = totalCost

    # @info "Running heuristic greedy with mode 3"
    # startTime = time()
    # solution = Solution(instanceSubSub)
    # ProfileView.@profview greedy!(solution, instanceSubSub; mode=3)
    # println("Cost after heuristic: $(compute_cost(instanceSubSub, solution))")
    # solveTime = get_elapsed_time(startTime)
    # feasible = is_feasible(instanceSubSub, solution)
    # totalCost = compute_cost(instanceSubSub, solution)
    # @info "Results" :solve_time = solveTime :feasible = feasible :total_cost = totalCost

    # println("Max length encountered for packing : $MAX_LENGTH")
    # println("Path recompuations needed : $GREEDY_RECOMPUTATION")

    _, solutionSub_LB = lower_bound_heuristic(instanceSubSub)
    lbCost = compute_cost(instanceSubSub, solutionSub_LB)

    # _, solutionSub_LB = lower_bound_heuristic(instanceSubSub; parallel=true)
    # lbCost = compute_cost(instanceSubSub, solutionSub_LB)

    # Mix greedy and lower bound 
    # @info "Running heuristic mix greedy and lower bound with mode 3"
    # startTime = time()
    # solution = Solution(instanceSubSub)
    # greedy!(solution, instanceSubSub; mode=3)
    # println("Cost after heuristic: $(compute_cost(instanceSubSub, solution))")
    # solveTime = get_elapsed_time(startTime)
    # feasible = is_feasible(instanceSubSub, solution)
    # totalCost = compute_cost(instanceSubSub, solution)
    # @info "Results" :solve_time = solveTime :feasible = feasible :total_cost = totalCost

    # Shortest delivery 
    # @info "Running heuristic shortest_delivery"
    # startTime = time()
    # solution = Solution(instanceSubSub)
    # shortest_delivery!(solution, instanceSubSub)
    # println("Cost after heuristic: $(compute_cost(instanceSubSub, solution))")
    # solveTime = get_elapsed_time(startTime)
    # feasible = is_feasible(instanceSubSub, solution)
    # totalCost = compute_cost(instanceSubSub, solution)
    # @info "Results" :solve_time = solveTime :feasible = feasible :total_cost = totalCost

    # Average delivery 
    @info "Running heuristic average delivery"
    startTime = time()
    solution = Solution(instanceSubSub)
    average_delivery!(solution, instanceSubSub)
    println("Cost after heuristic: $(compute_cost(instanceSubSub, solution))")
    solveTime = get_elapsed_time(startTime)
    feasible = is_feasible(instanceSubSub, solution)
    totalCost = compute_cost(instanceSubSub, solution)
    @info "Results" :solve_time = solveTime :feasible = feasible :total_cost = totalCost

    # Random delivery 
    # @info "Running heuristic random delivery"
    # startTime = time()
    # solution = Solution(instanceSubSub)
    # random_delivery!(solution, instanceSubSub)
    # println("Cost after heuristic: $(compute_cost(instanceSubSub, solution))")
    # solveTime = get_elapsed_time(startTime)
    # feasible = is_feasible(instanceSubSub, solution)
    # totalCost = compute_cost(instanceSubSub, solution)
    # @info "Results" :solve_time = solveTime :feasible = feasible :total_cost = totalCost

    # @info "Running heuristic milp lower bound"
    # startTime = time()
    # solution = Solution(instanceSubSub)
    # milp_lower_bound!(solution, instanceSubSub)
    # println("Cost after heuristic: $(compute_cost(instanceSubSub, solution))")
    # solveTime = get_elapsed_time(startTime)
    # feasible = is_feasible(instanceSubSub, solution)
    # totalCost = compute_cost(instanceSubSub, solution)
    # @info "Results" :solve_time = solveTime :feasible = feasible :total_cost = totalCost

    @info "Running heuristic fully outsourced"
    startTime = time()
    solution = Solution(instanceSubSub)
    fully_outsourced2!(solution, instanceSubSub)
    println("Cost after heuristic: $(compute_cost(instanceSubSub, solution))")
    solveTime = get_elapsed_time(startTime)
    feasible = is_feasible(instanceSubSub, solution)
    totalCost = compute_cost(instanceSubSub, solution)
    @info "Results" :solve_time = solveTime :feasible = feasible :total_cost = totalCost

    # Then try the lns

    # TODO : Test milp packing here to see what is there to gain

    # Choosing the best initial solution on which to apply local search 
    solution = solutionSub_LB
    # if lbCost < greedyCost
    #     solution = solutionSub_LB
    #     @info "Choosing lower bound solution as initial solution"
    # else
    #     @info "Choosing greedy solution as initial solution"
    # end

    # Then try the different local search heuristics 
    solution1, solution2 = deepcopy(solution), deepcopy(solution)

    # local_search!(solution, instanceSubSub)
    # local_search1!(solution1, instanceSubSub)
    # local_search2!(solution2, instanceSubSub)
    local_search3!(solution, instanceSubSub)

    sol = LNS2(solution, instanceSubSub)

    return 0

    # save("start_solution.jld2", "solution", solution)
    # println("Loading initial solution")
    # solution = load("start_solution.jld2", "solution")

    # _, solutionSubSub_GLS = greedy_or_lb_then_ls_heuristic(instanceSubSub; timeLimit=300)

    # local_search_heuristic!(solution, instanceSubSub; timeLimit=600, stepLimit=90)

    # TODO : need to compare just local search and LNS on the same time frame to see the difference
    # Without warm start diversity seems to lead to more improvement
    # Still need to see wether slope scaling helps

    # lns_heuristic!(
    #     solution, instanceSubSub; timeLimit=1800, lsTimeLimit=600, lsStepTimeLimit=90
    # )
    # println("Cost of solution : $(compute_cost(instanceSubSub, solution))")

    # TODO : do soluttion analysis function to print relevant KPIs

    # startCost = compute_cost(instanceSub, solutionSubSub_GLS)
    # costThreshold = 1e-2 * startCost
    # slope_scaling_cost_update!(instanceSub.timeSpaceGraph, Solution(instanceSub))
    # # slope_scaling_cost_update!(instanceSub.timeSpaceGraph, solutionSubSub_GLS)
    # ProfileView.@profile perturbate!(
    #     solutionSubSub_GLS,
    #     instanceSub,
    #     :single_plant,
    #     startCost,
    #     costThreshold;
    #     verbose=true,
    # )
    # local_search!(solutionSubSub_GLS, instanceSub; twoNode=true, timeLimit=300)

    # startCost = compute_cost(instanceSub, solutionSubSub_GLS)
    # # slope_scaling_cost_update!(instanceSub.timeSpaceGraph, solutionSubSub_GLS)
    # perturbate!(
    #     solutionSubSub_GLS, instanceSub, :reduce, startCost, costThreshold; verbose=true
    # )
    # local_search!(solutionSubSub_GLS, instanceSub; twoNode=true, timeLimit=300)

    # startCost = compute_cost(instanceSub, solutionSubSub_GLS)
    # # slope_scaling_cost_update!(instanceSub.timeSpaceGraph, solutionSubSub_GLS)
    # perturbate!(
    #     solutionSubSub_GLS,
    #     instanceSub,
    #     :two_shared_node,
    #     startCost,
    #     costThreshold;
    #     verbose=true,
    # )
    # local_search!(solutionSubSub_GLS, instanceSub; twoNode=true, timeLimit=300)

    # finalSolution = fuse_solutions(solution, solutionSub_LBF, instanceSub, instanceSubSub)

    # Test milp packing here to see what is there to gain

    # Cleaning final solution linears arcs
    # @info "Cleaning final solution before extraction"
    # bin_packing_improvement!(finalSolution, instanceSub; sorted=true, skipLinear=false)
    # clean_empty_bins!(finalSolution, instanceSub)

    # export only for the full instance
    # exportDir = joinpath(dirname(@__DIR__), "scripts", "export")
    # println("Exporting data to $exportDir")
    # write_solution(finalSolution, instanceSub; suffix="proposed", directory=dirname)
    # write_soluton(solutionSub_C, instanceSub; suffix="current", directory=dirname)

    return 0 # if things finished successfully
end