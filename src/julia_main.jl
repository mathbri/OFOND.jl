# File used to launch all kinds of scripts using OFOND package 

# using OFOND
using ProfileView
using JLD2
using Statistics
using Logging

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

function julia_main_test(
    instanceName::String="tiny", timeLimit::Int=300, capacityFactor::Float64=1.0
)
    println("\n######################################\n")
    println("Launching OFO Network Design (test)")
    println("\n######################################\n")

    @info "Test parameters" instanceName timeLimit capacityFactor

    # seaCapa = round(Int, DEFAULT_SEA_CAPACITY * capacityFactor)
    # global SEA_CAPACITY::Int = seaCapa

    # landCapa = round(Int, DEFAULT_LAND_CAPACITY * capacityFactor)
    # global LAND_CAPACITY::Int = landCapa

    #####################################################################
    # 1. Read instance and solution
    #####################################################################

    directory = joinpath(Base.dirname(@__DIR__), "scripts", "academic data")
    println("Reading data from $directory")
    # instanceName = "tiny"
    println("Reading instance $instanceName")
    node_file = joinpath(directory, "$(instanceName)_nodes.csv")
    leg_file = joinpath(directory, "$(instanceName)_legs.csv")
    com_file = joinpath(directory, "$(instanceName)_commodities.csv")
    # read instance 
    instance = read_instance(node_file, leg_file, com_file)
    # adding properties to the instance
    CAPACITIES = Int[]
    instance = add_properties(instance, tentative_first_fit, CAPACITIES)

    totVol = sum(sum(o.volume for o in b.orders) for b in instance.bundles)
    println("Instance volume : $(round(Int, totVol / VOLUME_FACTOR)) m3")

    # read solution
    sol_file = joinpath(directory, "$(instanceName)_routes.csv")
    solution = read_solution(instance, joinpath(directory, sol_file))

    # println("Exporting solution to $directory")
    # write_compact_solution(solution, instance; suffix=instanceName, directory=directory)

    # println("Reading back current solution")
    # sol_file = joinpath(directory, "$(instanceName)_routes2.csv")
    # solution = read_solution(instance, joinpath(directory, sol_file))
    println("\n######################################\n")

    #####################################################################
    # 2. Run all heuristics
    #####################################################################

    # Linear lower bound 
    run_simple_heursitic(instance, lower_bound!)
    println("\n######################################\n")

    run_simple_heursitic(instance, split_by_part_lower_bound!)
    println("\n######################################\n")

    # Load plan design lower bound 
    if length(instance.bundles) < 1200
        run_simple_heursitic(instance, milp_lower_bound!)
        println("\n######################################\n")
    end

    # Shortest delivery
    run_simple_heursitic(instance, shortest_delivery!)
    println("\n######################################\n")

    # Random delivery 
    run_simple_heursitic(instance, random_delivery!)
    println("\n######################################\n")

    # Average delivery 
    run_simple_heursitic(instance, average_delivery!)
    println("\n######################################\n")

    # Fully outsourced 
    run_simple_heursitic(instance, fully_outsourced2!)
    println("\n######################################\n")

    # Greedy 
    greedySol = run_simple_heursitic(instance, greedy!)
    println("\n######################################\n")

    if instanceName == "tiny"
        return 0
    end

    # Local search on current 
    # run_local_search(instance, local_search3!, solution, 30)
    # println("\n######################################\n")

    run_local_search(instance, local_search4!, solution, timeLimit)
    println("\n######################################\n")

    if instanceName == "extra_small"
        return 0
    end

    # Load plan design ils on current 
    run_local_search(instance, load_plan_design_ils!, solution, timeLimit)
    println("\n######################################\n")

    run_local_search(instance, load_plan_design_ils!, greedySol, timeLimit)
    println("\n######################################\n")

    run_local_search(instance, load_plan_design_ils2!, solution, timeLimit)
    println("\n######################################\n")

    # Plan by plant milp 
    # run_simple_heursitic(instance, plant_by_plant_milp!)
    # println("\n######################################\n")

    # return 0

    # ILS
    @info "Filtering with standard procedure"
    _, solution_LBF = lower_bound_filtering_heuristic(instance)
    println("Bundles filtered : $(count(x -> length(x) == 2, solution_LBF.bundlePaths))")

    instanceSub = extract_filtered_instance(instance, solution_LBF)
    instanceSub = add_properties(instanceSub, tentative_first_fit, CAPACITIES)

    @info "Constructing greedy, lower bound and mixed solution"
    solution_Mix = Solution(instanceSub)
    solution_G, solution_LB = mix_greedy_and_lower_bound!(solution_Mix, instanceSub)
    feasibles = [
        is_feasible(instanceSub, sol) for sol in [solution_Mix, solution_G, solution_LB]
    ]
    mixCost = compute_cost(instanceSub, solution_Mix)
    gCost = compute_cost(instanceSub, solution_G)
    lbCost = compute_cost(instanceSub, solution_LB)
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
    # local_search3!(solutionSub, instanceSub)
    local_search4!(solutionSub, instanceSub; timeLimit=timeLimit)

    # Faire le cost scaling et regarder si la solution obtenues en warm start a le même coût que celui calculé en dehors du milp
    # Si différence, regarder ou ca fait nimporte quoi

    # Applying ILS 
    pertLimit = round(Int, min(150, timeLimit / 5))
    lsLimit = round(Int, min(600, timeLimit / 5))
    ILS!(
        solutionSub,
        instanceSub;
        timeLimit=timeLimit,
        perturbTimeLimit=pertLimit,
        lsTimeLimit=lsLimit,
    )
    finalSolution = fuse_solutions(solutionSub, solution_LBF, instance, instanceSub)
    println("\n######################################\n")

    # Fully outsourced 
    run_simple_heursitic(instanceSub, fully_outsourced2!)
    println("\n######################################\n")

    return 0

    netGraph = instanceSub.networkGraph.graph
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

    return 0 # if things finished successfully
end

function julia_main_logged(
    instanceNames::Vector{String}=["tiny"], timeLimits::Vector{Int}=[300]
)
    for (instanceName, timeLimit) in zip(instanceNames, timeLimits)
        open("log_$instanceName.txt", "w") do file
            logger = SimpleLogger(file)
            global_logger(logger)
            redirect_stdout(file) do
                julia_main_test(instanceName, timeLimit)
            end
        end
    end
end

# function julia_main_logged(
#     instanceNames::Vector{String}=["tiny"], capacityFactors::Vector{Float64}=[1.0]
# )
#     for (instanceName, factor) in zip(instanceNames, capacityFactors)
#         open("log_$instanceName.txt", "w") do file
#             logger = SimpleLogger(file)
#             global_logger(logger)
#             redirect_stdout(file) do
#                 julia_main_test(instanceName, 3600, factor)
#             end
#         end
#     end
# end