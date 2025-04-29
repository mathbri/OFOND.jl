# File used to launch all kinds of scripts using OFOND package 

# using ProfileView
using JLD2
using Statistics

INPUT_FOLDER = joinpath(Base.dirname(@__DIR__), "scripts", "data_100425")
OUTPUT_FOLDER = joinpath(Base.dirname(@__DIR__), "scripts", "export")

NODE_FILE = "ND-MD-Geo_V5_preprocessing.csv"
LEG_FILE = "Legs_preprocessed.csv"
VOLUME_FILE = "Volumes_preprocessed.csv"
ROUTE_FILE = "route_Preprocessed.csv"
ANOMALY_FILE = "anomalies.csv"

function check_julia_main_input(
    inputFolder::String,
    node_file::String,
    leg_file::String,
    com_file::String,
    sol_file::String,
    outputFolder::String,
)
    if !isdir(inputFolder)
        throw(
            ArgumentError("Input folder argument given ($inputFolder) is not a directory")
        )
    end
    if !isdir(outputFolder)
        throw(
            ArgumentError("Output folder argument given ($outputFolder) is not a directory")
        )
    end
    if !isfile(node_file)
        throw(ArgumentError("Node file argument given ($node_file) is not a file"))
    end
    if !isfile(leg_file)
        throw(ArgumentError("Leg file argument given ($leg_file) is not a file"))
    end
    if !isfile(com_file)
        throw(ArgumentError("Volume file argument given ($com_file) is not a file"))
    end
    if !isfile(sol_file)
        throw(ArgumentError("Solution file argument given ($sol_file) is not a file"))
    end
end

function julia_main(;
    inputFolder::String=INPUT_FOLDER,
    nodeFile::String=NODE_FILE,
    legFile::String=LEG_FILE,
    volumeFile::String=VOLUME_FILE,
    routeFile::String=ROUTE_FILE,
    outputFolder::String=OUTPUT_FOLDER,
    useILS::Bool=false,
    useWeights::Bool=false,
    filterCurrentArcs::Bool=true,
)::Int
    juliaMainStart = time()

    # Read files based on arguments
    println("Launching OFOND Optimization")
    println("Reading data from $inputFolder")
    println("Exporting data to $outputFolder")

    # Reading instance base on files given
    node_file = joinpath(inputFolder, nodeFile)
    leg_file = joinpath(inputFolder, legFile)
    com_file = joinpath(inputFolder, volumeFile)
    anomaly_file = joinpath(outputFolder, ANOMALY_FILE)
    sol_file = joinpath(inputFolder, routeFile)

    check_julia_main_input(
        inputFolder, node_file, leg_file, com_file, sol_file, outputFolder
    )
    # Initialize anomaly file 
    open(anomaly_file, "w") do io
        println(io, join(ANOMALY_COLUMNS, ","))
    end

    # read instance 
    instance2D = read_instance(node_file, leg_file, com_file, anomaly_file)
    # adding properties to the instance
    CAPACITIES_V = Int[]
    instance2D = add_properties(instance2D, tentative_first_fit, CAPACITIES_V, anomaly_file)

    totVol = sum(sum(o.volume for o in b.orders) for b in instance2D.bundles)
    println("Instance volume : $(round(Int, totVol / VOLUME_FACTOR)) m3")
    totWei = sum(
        sum(sum(c.weight for c in o.content) for o in b.orders) for b in instance2D.bundles
    )
    println("Instance weight : $(round(Int, totWei / WEIGHT_FACTOR)) tons")

    # Read solution based on file given
    instance2D, solution2D = read_solution(instance2D, sol_file, anomaly_file)
    println("Cost of current solution (2D) : $(compute_cost(instance2D, solution2D))")

    # Creating hash to routeId dict 
    hashToRouteId = Dict{UInt,Int}()
    for (i, bundle) in enumerate(instance2D.bundles)
        hashToRouteId[bundle.hash] = i
    end

    # Exporting current solution
    println("Exporting current solution")
    write_solution(
        solution2D, instance2D, hashToRouteId; suffix="current", directory=outputFolder
    )

    # Transform here from 2D to 1D
    # CAPACITIES_V = Int[]
    instance1D = instance_1D(instance2D; mixing=useWeights)
    instance1D = add_properties(instance1D, tentative_first_fit, CAPACITIES_V, anomaly_file)
    sort_order_content!(instance1D)

    totVol = sum(sum(o.volume for o in b.orders) for b in instance1D.bundles)
    println("Instance volume : $(round(Int, totVol / VOLUME_FACTOR)) m3")
    totWei = sum(
        sum(sum(c.weight for c in o.content) for o in b.orders) for b in instance1D.bundles
    )
    println("Instance weight : $(round(Int, totWei / WEIGHT_FACTOR)) tons")

    # Computing current solution in 1D to get a reference also
    start = time()
    solution1D = Solution(instance1D)
    update_solution!(
        solution1D, instance1D, instance1D.bundles, solution2D.bundlePaths; sorted=true
    )
    totalCost = compute_cost(instance1D, solution1D)
    timeTaken = round(time() - start; digits=1)
    @info "Solution 1D constructed" :total_cost = totalCost :time = timeTaken
    println(
        "Most expensive arc in the network : $(maximum(a -> a.unitCost, instance1D.travelTimeGraph.networkArcs))",
    )

    # Reading instance again but ignoring current network
    if filterCurrentArcs
        instance2D = filter_current_arcs(instance2D)
        instance2D = add_properties(
            instance2D, tentative_first_fit, CAPACITIES_V, anomaly_file
        )
        instance1D = filter_current_arcs(instance1D)
        instance1D = add_properties(
            instance1D, tentative_first_fit, CAPACITIES_V, anomaly_file
        )
        sort_order_content!(instance1D)

        totVol = sum(sum(o.volume for o in b.orders) for b in instance1D.bundles)
        println("Instance volume : $(round(Int, totVol / VOLUME_FACTOR)) m3")

        totWei = sum(
            sum(sum(c.weight for c in o.content) for o in b.orders) for
            b in instance1D.bundles
        )
        println("Instance weight : $(round(Int, totWei / WEIGHT_FACTOR)) tons")
    end

    for node_label in labels(instance1D.networkGraph.graph)
        node = instance1D.networkGraph.graph[node_label]
        if node.volumeCost > EPS
            println(node)
        end
    end

    # Filtering procedure 
    _, solution_LBF = lower_bound_filtering_heuristic(instance1D)
    println(
        "Bundles actually filtered : $(count(x -> length(x) == 2, solution_LBF.bundlePaths))",
    )
    instanceSub = extract_filtered_instance(instance1D, solution_LBF)
    instanceSub = add_properties(
        instanceSub, tentative_first_fit, CAPACITIES_V, anomaly_file
    )

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
    solution_Mix = Solution(instanceSub)
    start = time()
    solution_G, solution_LB = mix_greedy_and_lower_bound!(solution_Mix, instanceSub)
    timeTaken = round(time() - start; digits=1)
    feasibles = [
        is_feasible(instanceSub, sol) for sol in [solution_Mix, solution_G, solution_LB]
    ]
    @assert all(feasibles)
    mixCost = compute_cost(instanceSub, solution_Mix)
    gCost = compute_cost(instanceSub, solution_G)
    lbCost = compute_cost(instanceSub, solution_LB)
    @info "Mixed heuristic results" :mixed_cost = mixCost :greedy_cost = gCost :lower_bound_cost =
        lbCost :time = timeTaken

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
    @info "Applying local search"
    local_search!(solutionSub, instanceSub; timeLimit=900, stepTimeLimit=30)

    # Applying ILS 
    if useILS
        ILS!(
            solutionSub,
            instanceSub;
            timeLimit=1800,
            perturbTimeLimit=150,
            lsTimeLimit=600,
            lsStepTimeLimit=150,
        )
    end

    @info "Enforcing strict admissibility before extraction"
    enforce_strict_admissibility!(solutionSub, instanceSub)
    println("Is feasible : $(is_feasible(instanceSub, solutionSub))")

    # Fusing solutions
    finalSolution1D = fuse_solutions(solutionSub, solution_LBF, instance1D, instanceSub)
    println("Is feasible : $(is_feasible(instance1D, finalSolution1D))")

    # Un-transform here from 1D to 2D
    finalSolution = Solution(instance2D)
    @info "Transforming back to explicit 2D solution"
    for (i, bundle) in enumerate(instance2D.bundles)
        # Getting bundle idx
        bundleIdx1D = if bundle == instance1D.bundles[bundle.idx]
            bundle.idx
        else
            findfirst(b -> b == bundle, instance1D.bundles)
        end
        if isnothing(bundleIdx1D)
            @error "Bundle in 2D instance not found in 1D instance" bundle
        end
        bundlePath1D = finalSolution1D.bundlePaths[bundleIdx1D]
        bundlePath2D = project_on_sub_instance(bundlePath1D, instance1D, instance2D)
        add_bundle!(finalSolution, instance2D, bundle, bundlePath2D)
        i % 10 == 0 && print("|")
    end
    println()
    println("Is feasible : $(is_feasible(instance2D, finalSolution))")

    # TODO : add explicit 2D bin packing improvement, this was made for 1D instances
    # @info "Optimizing final packings"
    # COMMO = Commodity[]
    # bin_packing_improvement!(finalSolution, instance2D, COMMO, CAPACITIES_V)
    # println("Is feasible : $(is_feasible(instance2D, finalSolution))")

    @info "Cleaning empty bins"
    clean_empty_bins!(finalSolution, instance2D)
    println("Is feasible : $(is_feasible(instance2D, finalSolution))")

    println("Cost of 2D proposed solution : $(compute_cost(instance2D, finalSolution))")

    println("Exporting proposed solution to $outputFolder")
    write_solution(
        finalSolution, instance2D, hashToRouteId; suffix="proposed", directory=outputFolder
    )

    juliaMainTime = round(time() - juliaMainStart; digits=1)
    @info "Total Julia Main time : $juliaMainTime"

    return 0 # if things finished successfully
end
