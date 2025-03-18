# File used to launch all kinds of scripts using OFOND package 

# TODO : test the correct execution of all code on the multiple instances available

# using OFOND
using ProfileView
using JLD2
using Statistics

INPUT_FOLDER = joinpath(Base.dirname(@__DIR__), "scripts", "data_test")
OUTPUT_FOLDER = joinpath(Base.dirname(@__DIR__), "scripts", "export")

NODE_FILE = "ND-MD-Geo_V5_preprocessing 1.csv"
LEG_FILE = "Legs_preprocessed 1.csv"
VOLUME_FILE = "Volumes_preprocessed 1.csv"
ROUTE_FILE = "route_Preprocessed 1.csv"

function julia_main(;
    inputFolder::String=INPUT_FOLDER,
    nodeFile::String=NODE_FILE,
    legFile::String=LEG_FILE,
    volumeFile::String=VOLUME_FILE,
    routeFile::String=ROUTE_FILE,
    outputFolder::String=OUTPUT_FOLDER,
    useILS::Bool=true,
    useWeights::Bool=true,
)::Int
    # Read files based on arguments
    println("Launching OFOND Optimization")
    if !isdir(inputFolder)
        throw(
            ArgumentError("Input folder argument given ($inputFolder) is not a directory")
        )
    end
    println("Reading data from $input_folder")

    # Reading instance base on files given
    node_file = joinpath(inputFolder, nodeFile)
    if !isfile(node_file)
        throw(ArgumentError("Node file argument given ($node_file) is not a file"))
    end
    leg_file = joinpath(inputFolder, legFile)
    if !isfile(leg_file)
        throw(ArgumentError("Leg file argument given ($leg_file) is not a file"))
    end
    com_file = joinpath(inputFolder, volumeFile)
    if !isfile(com_file)
        throw(ArgumentError("Volume file argument given ($com_file) is not a file"))
    end
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

    # Read solution based on file given
    sol_file = joinpath(inputFolder, routeFile)
    if !isfile(sol_file)
        throw(ArgumentError("Solution file argument given ($sol_file) is not a file"))
    end
    # length(ARGS) >= 5 && isfile(ARGS[5]) && (sol_file = ARGS[5])
    solution2D = read_solution(instance2D, sol_file)
    println("Cost of current solution (2D) : $(compute_cost(instance2D, solution2D))")

    # Exporting current solution
    if !isdir(outputFolder)
        throw(
            ArgumentError("Output folder argument given ($outputFolder) is not a directory")
        )
    end

    println("Exporting current solution to $exportDir")
    clean_empty_bins!(solution2D, instance2D)
    # write_solution(solution2D, instance2D; suffix="current", directory=exportDir)

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

    @info "Constructing greedy, lower bound and mixed solution"
    solution_Mix = Solution(instanceSubSub)
    solution_G, solution_LB = mix_greedy_and_lower_bound!(solution_Mix, instanceSubSub)
    feasibles = [
        is_feasible(instanceSubSub, sol) for sol in [solution_Mix, solution_G, solution_LB]
    ]
    @assert all(feasibles)
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
    local_search!(solutionSub, instanceSubSub; timeLimit=300, stepTimeLimit=90)

    # Applying ILS 
    if useILS
        ILS!(
            solutionSub,
            instanceSubSub;
            timeLimit=1800,
            perturbTimeLimit=300,
            lsTimeLimit=600,
            lsStepTimeLimit=90,
        )
    end

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
    enforce_strict_admissibility!(finalSolution, instance)
    bin_packing_improvement!(
        finalSolution, instance, Commodity[], Int[]; sorted=true, skipLinear=false
    )
    clean_empty_bins!(finalSolution, instance)

    println("Exporting proposed solution to $exportDir")
    write_solution(finalSolution, instance2D; suffix="proposed", directory=exportDir)

    return 0 # if things finished successfully
end
