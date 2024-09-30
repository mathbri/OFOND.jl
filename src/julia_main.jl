# File used to launch all kinds of scripts using OFOND package 

# using OFOND
using ProfileView
using JLD2

function julia_main()::Cint
    # Read files based on ARGS
    println("Launching OFO Network Design")
    println("Arguments : ", ARGS)
    directory = joinpath(Base.dirname(@__DIR__), "scripts", "data")
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
    node_file = joinpath(directory, "GeoDataProcessed_LC.csv")
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
    leg_file = joinpath(directory, "LegDataProcessed_NV1.csv")
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
    com_file = joinpath(directory, "VolumeDataProcessed_SC.csv")
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

    # adding properties to the instance
    CAPACITIES = Int[]
    instance = add_properties(instance, tentative_first_fit, CAPACITIES)

    # read solution
    sol_file = joinpath(directory, "RouteDataProcessed.csv")
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
    solution = read_solution(instance, joinpath(directory, sol_file))

    # cut it into smaller instances 
    # instanceSub = extract_sub_instance(instance; country="FRANCE", timeHorizon=6)
    # instanceSub = extract_sub_instance(instance; continent="Western Europe", timeHorizon=9)
    instanceSub = instance
    # adding properties to the instance
    # instanceSub = add_properties(instanceSub, tentative_first_fit)
    # solutionSub_C = extract_sub_solution(solution, instance, instanceSub)
    solutionSub_C = solution

    # Filtering procedure 
    _, solutionSub_LBF = lower_bound_filtering_heuristic(instanceSub)
    println(
        "Bundles actually filtered : $(count(x -> length(x) == 2, solutionSub_LBF.bundlePaths))",
    )
    instanceSubSub = extract_filtered_instance(instanceSub, solutionSub_LBF)
    instanceSubSub = add_properties(instanceSubSub, tentative_first_fit, CAPACITIES)

    # Greedy or Lower Bound than Local Search heuristic
    _, solutionSubSub_GLS = greedy_or_lb_then_ls_heuristic(instanceSubSub; timeLimit=300)

    # Fusing solutions
    finalSolution = fuse_solutions(
        solutionSubSub_GLS, solutionSub_LBF, instanceSub, instanceSubSub
    )

    # Cleaning final solution linears arcs
    @info "Cleaning final solution before extraction"
    bin_packing_improvement!(finalSolution, instanceSub; sorted=true, skipLinear=false)
    clean_empty_bins!(finalSolution, instanceSub)

    # export only for the full instance
    directory = joinpath(dirname(@__DIR__), "scripts", "export")
    if length(ARGS) >= 6
        if isdir(ARGS[6])
            directory = ARGS[6]
        else
            @warn "Sixth argument (export directory) is not a directory, switching to default" :directory_given = ARGS[6] :default =
                directory
        end
    end
    # length(ARGS) >= 6 && isdir(directory) && (directory = ARGS[6])
    println("Exporting data to $directory")
    write_solution(finalSolution, instanceSub; suffix="proposed", directory=dirname)
    write_soluton(solutionSub_C, instanceSub; suffix="current", directory=dirname)

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
    # instanceSub = extract_sub_instance(instance; country="FRANCE", timeHorizon=6)
    instanceSub = extract_sub_instance2(
        instance;
        continents=["Western Europe", "South America", "South-East Asia"],
        timeHorizon=9,
    )

    # instanceSub = instance
    # adding properties to the instance
    # instanceSub = add_properties(instanceSub, tentative_first_fit, CAPACITIES)
    # solutionSub_C = extract_sub_solution(solution, instance, instanceSub)
    # solutionSub_C = solution

    # test algorithms  

    _, solutionSub_LBF = lower_bound_filtering_heuristic(instanceSub)
    println(
        "Bundles actually filtered : $(count(x -> length(x) == 2, solutionSub_LBF.bundlePaths))",
    )

    instanceSubSub = extract_filtered_instance(instanceSub, solutionSub_LBF)
    instanceSubSub = add_properties(instanceSubSub, tentative_first_fit, CAPACITIES)

    solutionSub_C = extract_sub_solution(solution, instance, instanceSubSub)
    # solutionSub_C = solution

    # save("instance.jld2", "instance", instanceSubSub)

    netGraph = instanceSubSub.networkGraph.graph
    nSuppliers = count(lab -> netGraph[lab].type == :supplier, labels(netGraph))
    nPlants = count(lab -> netGraph[lab].type == :plant, labels(netGraph))
    println("$nSuppliers suppliers and $nPlants plants")

    nPlat = length(labels(netGraph)) - nSuppliers - nPlants
    meanPlatCost = sum(lab -> netGraph[lab].volumeCost, labels(netGraph)) / nPlat
    nCom = sum(b -> sum(o -> length(o.content), b.orders), instance.bundles)
    meanSize =
        sum(b -> sum(o -> sum(c -> c.size, o.content), b.orders), instance.bundles) / nCom /
        VOLUME_FACTOR
    meanCost =
        sum(b -> sum(o -> sum(c -> c.stockCost, o.content), b.orders), instance.bundles) /
        nCom
    println(
        "Mean platform cost $meanPlatCost and mean size $meanSize and mean cost $meanCost"
    )
    allTransCost = sum(a -> netGraph[a[1], a[2]].unitCost, edge_labels(netGraph))
    allCarbCost = sum(a -> netGraph[a[1], a[2]].carbonCost, edge_labels(netGraph))
    println("Share of transportation cost $(allTransCost / (allTransCost + allCarbCost))")
    # return 0

    # println("Loading instance")
    # instanceSubSub = load("instance.jld2", "instance")

    # _, solutionSub_SD = shortest_delivery_heuristic(instanceSub)
    # global MAX_LENGTH, GREEDY_RECOMPUTATION = 0, 0

    _, solutionSub_G = greedy_heuristic(instanceSubSub)
    greedyCost = compute_cost(instanceSubSub, solutionSub_G)

    # println("Max length encountered for packing : $MAX_LENGTH")
    # println("Path recompuations needed : $GREEDY_RECOMPUTATION")

    _, solutionSub_LB = lower_bound_heuristic(instanceSubSub)
    lbCost = compute_cost(instanceSubSub, solutionSub_LB)

    # Choosing the best initial solution on which to apply local search 
    solution = solutionSub_G
    if lbCost < greedyCost
        solution = solutionSub_LB
        @info "Choosing lower bound solution as initial solution"
    else
        @info "Choosing greedy solution as initial solution"
    end

    # save("start_solution.jld2", "solution", solution)
    # println("Loading initial solution")
    # solution = load("start_solution.jld2", "solution")

    # _, solutionSubSub_GLS = greedy_or_lb_then_ls_heuristic(instanceSubSub; timeLimit=300)

    local_search_heuristic!(solution, instanceSubSub; timeLimit=600, stepLimit=90)

    # TODO : need to compare just local search and LNS on the same time frame to see the difference
    # Without warm start diversity seems to lead to more improvement
    # Still need to see wether slope scaling helps

    lns_heuristic!(
        solution, instanceSubSub; timeLimit=1800, lsTimeLimit=600, lsStepTimeLimit=90
    )
    # println("Cost of solution : $(compute_cost(instanceSubSub, solution))")

    # TODO : do soluttion analysis function to print relevant KPIs

    # startCost = compute_cost(instanceSubSub, solutionSubSub_GLS)
    # costThreshold = 1e-2 * startCost
    # slope_scaling_cost_update!(instanceSubSub.timeSpaceGraph, Solution(instanceSubSub))
    # # slope_scaling_cost_update!(instanceSubSub.timeSpaceGraph, solutionSubSub_GLS)
    # ProfileView.@profile perturbate!(
    #     solutionSubSub_GLS,
    #     instanceSubSub,
    #     :single_plant,
    #     startCost,
    #     costThreshold;
    #     verbose=true,
    # )
    # local_search!(solutionSubSub_GLS, instanceSubSub; twoNode=true, timeLimit=300)

    # startCost = compute_cost(instanceSubSub, solutionSubSub_GLS)
    # # slope_scaling_cost_update!(instanceSubSub.timeSpaceGraph, solutionSubSub_GLS)
    # perturbate!(
    #     solutionSubSub_GLS, instanceSubSub, :reduce, startCost, costThreshold; verbose=true
    # )
    # local_search!(solutionSubSub_GLS, instanceSubSub; twoNode=true, timeLimit=300)

    # startCost = compute_cost(instanceSubSub, solutionSubSub_GLS)
    # # slope_scaling_cost_update!(instanceSubSub.timeSpaceGraph, solutionSubSub_GLS)
    # perturbate!(
    #     solutionSubSub_GLS,
    #     instanceSubSub,
    #     :two_shared_node,
    #     startCost,
    #     costThreshold;
    #     verbose=true,
    # )
    # local_search!(solutionSubSub_GLS, instanceSubSub; twoNode=true, timeLimit=300)

    # finalSolution = fuse_solutions(solution, solutionSub_LBF, instanceSub, instanceSubSub)

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