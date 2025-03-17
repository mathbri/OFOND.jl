# File used to launch all kinds of scripts using OFOND package 

# using OFOND
# using ProfileView

function julia_main()::Cint
    # Read files based on ARGS
    println("Launching OFO Network Design")
    println("Arguments : ", ARGS)
    directory = joinpath(Base.dirname(@__DIR__), "scripts", "data_170325")
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
    node_file = joinpath(directory, "ND-MD-Geo_V5_preprocessing.csv")
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
    leg_file = joinpath(directory, "Legs_preprocessed.csv")
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
    com_file = joinpath(directory, "Volumes_preprocessed.csv")
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
    instance2D = read_instance(node_file, leg_file, com_file)
    # println("Instance dates : $(instance.dates)")

    # adding properties to the instance
    CAPACITIES_V, CAPACITIES_W = Int[], Int[]
    instance2D = add_properties(instance2D, tentative_first_fit, CAPACITIES_V)

    totVol = sum(sum(o.volume for o in b.orders) for b in instance2D.bundles)
    println("Instance volume : $(round(Int, totVol / VOLUME_FACTOR)) m3")
    totWei = sum(
        sum(sum(c.weight for c in o.content) for o in b.orders) for b in instance2D.bundles
    )
    println("Instance weight : $(round(Int, totWei / WEIGHT_FACTOR)) tons")

    # read solution
    sol_file = joinpath(directory, "route_Preprocessed.csv")
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
    solution2D = read_solution(instance2D, sol_file)
    println("Cost of current solution (2D) : $(compute_cost(instance2D, solution2D))")

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
    clean_empty_bins!(solution2D, instance2D)
    write_solution(solution2D, instance2D; suffix="current", directory=exportDir)

    # Transform here from 2D to 1D
    CAPACITIES_V = Int[]
    instance1D = instance_1D(instance2D; mixing=true)
    instance1D = add_properties(instance1D, tentative_first_fit, CAPACITIES_V)

    # Computing current solution in 1D to get a reference also
    solution1D = Solution(instance1D)
    update_solution!(solution1D, instance1D, instance1D.bundles, solution2D.bundlePaths)
    println("Cost of current solution (1D) : $(compute_cost(instance1D, solution1D))")

    # Reading instance again but ignoring current network
    instance2D = read_instance(node_file, leg_file, com_file; ignoreCurrent=true)
    instance2D = add_properties(instance2D, tentative_first_fit, CAPACITIES_V)

    # # Transform here from 2D to 1D
    instance1D = instance_1D(instance2D; mixing=true)
    instance1D = add_properties(instance1D, tentative_first_fit, CAPACITIES_V)

    totVol = sum(sum(o.volume for o in b.orders) for b in instance1D.bundles)
    println("Instance volume : $(round(Int, totVol / VOLUME_FACTOR)) m3")

    totWei = sum(
        sum(sum(c.weight for c in o.content) for o in b.orders) for b in instance1D.bundles
    )
    println("Instance weight : $(round(Int, totWei / WEIGHT_FACTOR)) tons")

    # Filtering procedure 
    _, solution_LBF = lower_bound_filtering_heuristic(instance1D)
    println(
        "Bundles actually filtered : $(count(x -> length(x) == 2, solution_LBF.bundlePaths))",
    )
    instanceSub = extract_filtered_instance(instance1D, solution_LBF)
    instanceSub = add_properties(instanceSub, tentative_first_fit, CAPACITIES_V)

    totVol = sum(sum(o.volume for o in b.orders) for b in instanceSub.bundles)
    println("Instance volume : $(round(Int, totVol / VOLUME_FACTOR)) m3")
    totWei = sum(
        sum(sum(c.weight for c in o.content) for o in b.orders) for b in instanceSub.bundles
    )
    println("Instance weight : $(round(Int, totWei / WEIGHT_FACTOR)) tons")
    println(
        "Common arcs in travel time graph : $(count(x -> x.type in BP_ARC_TYPES, instanceSub.travelTimeGraph.networkArcs))",
    )

    # return 0

    # Greedy or Lower Bound than Local Search heuristic
    _, solutionSub_GLS = greedy_or_lb_then_ls_heuristic(instanceSub; timeLimit=30)

    # Fusing solutions
    finalSolution1D = fuse_solutions(solutionSub_GLS, solution_LBF, instance1D, instanceSub)

    # Un-transform here from 1D to 2D
    finalSolution = Solution(instance2D)
    update_solution!(
        finalSolution, instance2D, instance2D.bundles, finalSolution1D.bundlePaths
    )
    println("Cost of 2D proposed solution : $(compute_cost(instance2D, finalSolution))")

    # Cleaning final solution linears arcs
    @info "Cleaning final solution before extraction"
    bin_packing_improvement!(finalSolution, instance2D; sorted=true, skipLinear=false)
    clean_empty_bins!(finalSolution, instance2D)

    # length(ARGS) >= 6 && isdir(directory) && (directory = ARGS[6])
    println("Exporting proposed solution to $exportDir")
    write_solution(finalSolution, instance2D; suffix="proposed", directory=exportDir)

    return 0 # if things finished successfully
end

function julia_main_test()
    println("Launching OFO Network Design (test)")
    directory = joinpath(Base.dirname(@__DIR__), "scripts", "data")
    println("Reading data from $directory")
    node_file = joinpath(directory, "GeoDataProcessed_LC.csv")
    leg_file = joinpath(directory, "LegDataProcessed_NV1.csv")
    com_file = joinpath(directory, "VolumeDataProcessed_SC.csv")
    # read instance 
    instance = read_instance(node_file, leg_file, com_file)
    # adding properties to the instance
    CAPACITIES = Int[]
    instance = add_properties(instance, tentative_first_fit, CAPACITIES)
    # read solution
    sol_file = joinpath(directory, "RouteDataProcessed.csv")
    solution = read_solution(instance, joinpath(directory, sol_file))

    # cut it into smaller instances 
    # instance = extract_sub_instance(instance; country="FRANCE", timeHorizon=6)
    # instance = extract_sub_instance(instance; continent="Western Europe", timeHorizon=9)
    instance = instance
    # adding properties to the instance
    # instance = add_properties(instance, tentative_first_fit)
    # solutionSub_C = extract_sub_solution(solution, instance, instance)
    solutionSub_C = solution

    # test algorithms  

    _, solution_LBF = lower_bound_filtering_heuristic(instance)
    println(
        "Bundles actually filtered : $(count(x -> length(x) == 2, solution_LBF.bundlePaths))",
    )

    instanceSub = extract_filtered_instance(instance, solution_LBF)
    instanceSub = add_properties(instanceSub, tentative_first_fit, CAPACITIES)

    # _, solutionSub_SD = shortest_delivery_heuristic(instance)
    # global MAX_LENGTH, GREEDY_RECOMPUTATION = 0, 0
    _, solutionSub_G = greedy_heuristic(instanceSub)
    greedycost = compute_cost(instanceSub, solutionSub_G)

    # println("Max length encountered for packing : $MAX_LENGTH")
    # println("Path recompuations needed : $GREEDY_RECOMPUTATION")

    _, solutionSub_LB = lower_bound_heuristic(instanceSub)
    lbCost = compute_cost(instanceSub, solutionSub_LB)

    # Choosing the best initial solution on which to apply local search 
    solution = solutionSub_G
    if lbCost < greedyCost
        solution = solutionSub_LB
        @info "Choosing lower bound solution as initial solution"
    else
        @info "Choosing greedy solution as initial solution"
    end

    # _, solutionSubSub_GLS = greedy_or_lb_then_ls_heuristic(instanceSub; timeLimit=300)

    _, solutionSubSub_GLS = local_search_heuristic!(solution, instanceSub; timeLimit=300)

    # TODO : need to compare just local search and LNS on the same time frame to see the difference
    # Without warm start diversity seems to lead to more improvement
    # Still need to see wether slope scaling helps

    # ProfileView.@profview lns_heuristic!(solutionSubSub_GLS, instanceSub; timeLimit=300)
    # println("Cost of solution : $(compute_cost(instanceSub, solutionSubSub_GLS))")

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

    finalSolution = fuse_solutions(solutionSubSub_GLS, solution_LBF, instance, instanceSub)

    # Cleaning final solution linears arcs
    @info "Cleaning final solution before extraction"
    bin_packing_improvement!(finalSolution, instance; sorted=true, skipLinear=false)
    clean_empty_bins!(finalSolution, instance)

    # export only for the full instance
    directory = joinpath(dirname(@__DIR__), "scripts", "export")
    println("Exporting data to $directory")
    write_solution(finalSolution, instance; suffix="proposed", directory=dirname)
    write_soluton(solutionSub_C, instance; suffix="current", directory=dirname)

    return 0 # if things finished successfully
end