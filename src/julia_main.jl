# File used to launch all kinds of scripts using OFOND package 

# using OFOND
using ProfileView

function julia_main()::Cint
    # do something based on ARGS?
    println("Launching OFO Network Design")
    # read instance 
    directory = joinpath(Base.dirname(@__DIR__), "scripts", "data")
    println("Reading data from $directory")
    instance = read_instance(
        "$directory\\GeoDataProcessed_LC.csv",
        "$directory\\LegDataProcessed_NV1.csv",
        "$directory\\VolumeDataProcessed_SC.csv",
    )
    # adding properties to the instance
    instance = add_properties(instance, tentative_first_fit)

    # read solution
    solution = read_solution(instance, "$directory\\RouteDataProcessed.csv")

    # cut it into smaller instances 
    # instanceSub = extract_sub_instance(instance; country="FRANCE", timeHorizon=6)
    # instanceSub = extract_sub_instance(instance; continent="Western Europe", timeHorizon=9)
    instanceSub = instance
    # adding properties to the instance
    # instanceSub = add_properties(instanceSub, tentative_first_fit)
    # solutionSub_C = extract_sub_solution(solution, instance, instanceSub)
    solutionSub_C = solution

    # test algorithms  

    _, solutionSub_LBF = lower_bound_filtering_heuristic(instanceSub)
    println(
        "Bundles actually filtered : $(count(x -> length(x) == 2, solutionSub_LBF.bundlePaths))",
    )

    instanceSubSub = extract_filtered_instance(instanceSub, solutionSub_LBF)
    instanceSubSub = add_properties(instanceSubSub, tentative_first_fit)

    startTime = time()
    newSol1 = deepcopy(solutionSub_LBF)
    println("Time for a standard deepcopy : $(get_elapsed_time(startTime))")

    startTime = time()
    newSol1 = my_deepcopy(solutionSub_LBF)
    println("Time for a custom deepcopy : $(get_elapsed_time(startTime))")

    # _, solutionSub_SD = shortest_delivery_heuristic(instanceSub)
    # global MAX_LENGTH, GREEDY_RECOMPUTATION = 0, 0
    # _, solutionSub_G = greedy_heuristic(instanceSubSub)
    # println("Max length encountered for packing : $MAX_LENGTH")
    # println("Path recompuations needed : $GREEDY_RECOMPUTATION")

    # _, solutionSub_LB = lower_bound_heuristic(instanceSubSub)
    _, solutionSubSub_GLS = greedy_then_ls_heuristic(instanceSubSub; timeLimit=300)

    finalSolution = fuse_solutions(
        solutionSubSub_GLS, solutionSub_LBF, instanceSub, instanceSubSub
    )

    # export only for the full instance
    dirname = joinpath(@__DIR__, "export")
    write_solution(finalSolution, instanceSub; suffix="proposed", directory=dirname)
    write_soluton(solutionSub_C, instanceSub; suffix="current", directory=dirname)

    return 0 # if things finished successfully
end