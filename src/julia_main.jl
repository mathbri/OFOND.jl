# File used to launch all kinds of scripts using OFOND package 

# using OFOND
using ProfileView

function julia_main()::Cint
    # Read files based on ARGS?
    println("Launching OFO Network Design")
    directory = joinpath(Base.dirname(@__DIR__), "scripts", "data")
    length(ARGS) >= 1 && isdir(ARGS[1]) && (directory = ARGS[1])
    println("Reading data from $directory")
    node_file = "GeoDataProcessed_LC.csv"
    length(ARGS) >= 2 && isfile(ARGS[2]) && (node_file = ARGS[2])
    leg_file = "LegDataProcessed_NV1.csv"
    length(ARGS) >= 3 && isfile(ARGS[3]) && (leg_file = ARGS[3])
    com_file = "VolumeDataProcessed_SC.csv"
    length(ARGS) >= 4 && isfile(ARGS[4]) && (com_file = ARGS[4])
    # read instance 
    instance = read_instance(
        "$directory\\$node_file", "$directory\\$leg_file", "$directory\\$com_file"
    )

    # "global" vector used for efficiency
    CAPACITIES = Int[]

    # adding properties to the instance
    instance = add_properties(instance, tentative_first_fit, CAPACITIES)

    # read solution
    # sol_file = "RouteDataProcessed.csv"
    # length(ARGS) >= 5 && isfile(ARGS[5]) && (sol_file = ARGS[5])
    # solution = read_solution(instance, "$directory\\$sol_file")

    # cut it into smaller instances 
    # instanceSub = extract_sub_instance(instance; country="FRANCE", timeHorizon=6)
    # instanceSub = extract_sub_instance(instance; continent="Western Europe", timeHorizon=9)
    instanceSub = instance
    # adding properties to the instance
    # instanceSub = add_properties(instanceSub, tentative_first_fit)
    # solutionSub_C = extract_sub_solution(solution, instance, instanceSub)
    # solutionSub_C = solution

    # test algorithms  

    _, solutionSub_LBF = lower_bound_filtering_heuristic(instanceSub)
    println(
        "Bundles actually filtered : $(count(x -> length(x) == 2, solutionSub_LBF.bundlePaths))",
    )

    instanceSubSub = extract_filtered_instance(instanceSub, solutionSub_LBF)
    instanceSubSub = add_properties(instanceSubSub, tentative_first_fit, CAPACITIES)

    # startTime = time()
    # newSol1 = deepcopy(solutionSub_LBF)
    # println("Time for a standard deepcopy : $(get_elapsed_time(startTime))")

    # startTime = time()
    # newSol1 = my_deepcopy(solutionSub_LBF)
    # println("Time for a custom deepcopy : $(get_elapsed_time(startTime))")

    # _, solutionSub_SD = shortest_delivery_heuristic(instanceSub)
    # global MAX_LENGTH, GREEDY_RECOMPUTATION = 0, 0
    # _, solutionSub_G = greedy_heuristic(instanceSubSub)
    # println("Max length encountered for packing : $MAX_LENGTH")
    # println("Path recompuations needed : $GREEDY_RECOMPUTATION")

    # _, solutionSub_LB = lower_bound_heuristic(instanceSubSub)
    _, solutionSubSub_GLS = greedy_or_lb_then_ls_heuristic(instanceSubSub; timeLimit=300)

    finalSolution = fuse_solutions(
        solutionSubSub_GLS, solutionSub_LBF, instanceSub, instanceSubSub
    )

    # export only for the full instance
    directory = joinpath(dirname(@__DIR__), "scripts", "export")
    length(ARGS) >= 6 && isdir(directory) && (directory = ARGS[6])
    println("Exporting data to $directory")
    write_solution(finalSolution, instanceSub; suffix="proposed", directory=dirname)
    write_soluton(solutionSub_C, instanceSub; suffix="current", directory=dirname)

    return 0 # if things finished successfully
end