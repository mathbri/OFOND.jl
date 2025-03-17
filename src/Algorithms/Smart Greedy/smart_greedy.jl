# Train the statistical model on a solution (or multiple solutions ?)

# We start by doing the code for training on a single instance to be able to replay it multiple times faster with slight modifications

###########################################################################################
##################################   Dataset   ###########################################         
###########################################################################################

# Transform an instance, a solution and a bundle into a matrix of features per arc
function smart_greedy_features(
    instance::Instance, solution::Solution, bundle::Bundle, it::Int, CAPA::Vector{Int}
)
    return vcat(
        common_static_features(instance),
        bundle_static_features(instance, bundle, CAPA),
        bundle_dynamic_features(instance, solution, bundle, it, CAPA),
    )
end

# Create the dataset associated to an instance and a solution
# Dataset : length(bundles) vector of length(features) x length(arcs) matrix
function create_dataset(instance::Instance, solution::Solution)
    dataset = Vector{Matrix{Float64}}(undef, length(instance.bundles))
    # True paths are already known
    truePaths = deepcopy(solution.bundlePaths)
    # Deepcopy the solution (with my own method for more efficiency) to modify it without modifying the original
    sol = my_deepcopy(solution)
    # Sorting bundles by reverse order of greedy insertion
    sortedBundleIdxs = sortperm(instance.bundles; by=bun -> bun.maxPackSize)
    B, CAPA = length(sortedBundleIdxs), Int[]
    # For each bundle, reverting the solution to the state before its insertion and computing arc features
    for (i, bundleIdx) in enumerate(sortedBundleIdxs)
        bundle = instance.bundles[bundleIdx]
        bundlePath = sol.bundlePaths[bundleIdx]
        # Removing bundle from solution
        update_solution!(sol, instance, bundle, bundlePath; remove=true, sorted=true)
        # Computing bundle features
        bundleFeatures = smart_greedy_features(instance, sol, bundle, B - i, CAPA)
        push!(dataset, bundleFeatures)
    end
    return dataset, truePaths
end

# Create the dataset associated with an instance not yet solved
function create_dataset(instance::Instance)
    solution = Solution(instance)
    lns_heuristic!(solution, instance; timeLimit=10, lsTimeLimit=10)
    return create_dataset(instance, solution)
end

# Divide dataset into train and test
function divide_dataset(dataset::Vector{Matrix{Float64}}, truePaths::Vector{Vector{Int}})
    B = length(dataset)
    # Divide instance bundles into 80% train and 20% test
    allBunIdxs = shuffle(1:B)
    nTrain = round(Int, 0.8 * B)
    trainIdxs = allBunIdxs[1:nTrain]
    testIdxs = allBunIdxs[(nTrain + 1):end]
    nTest = length(testIdxs)
    # Dividing data
    trainBundles = instance.bundles[trainIdxs]
    trainData = allData[trainIdxs]
    trainPaths = allPaths[trainIdxs]
    testBundles = instance.bundles[testIdxs]
    testData = allData[testIdxs]
    testPaths = allPaths[testIdxs]
    return trainBundles, trainData, trainPaths, testBundles, testData, testPaths
end

###########################################################################################
#################################   Inference   ###########################################         
###########################################################################################

# Predictor to be used when the model is fully trained
function smart_greedy_predictor(
    model::Chain,
    instance::Instance,
    solution::Solution,
    bundle::Bundle,
    it::Int,
    CAPA::Vector{Int},
)
    # Encode the instance and bundle features
    features = smart_greedy_features(instance, solution, bundle, it, CAPA)
    # Give the features to the model
    theta = model(features)
    # Compute the shortest path given the model output
    predictedPath = predicted_shortest_path(theta; instance, bundle)
    return predictedPath
end

# Smart Greedy heuristic function
# Nearly the same as greedy but instaed of update cost matrix we have the inference of the statistical model
function smart_greedy!(solution::Solution, instance::Instance, trainedModel::Chain)
    totalCost, B, CAPA = 0.0, length(sortedBundleIdxs), Int[]
    print("Smart Greedy introduction progress : ")
    percentIdx = ceil(Int, B / 100)
    # Compute all paths with the predicted costs
    for (i, bundle) in enumerate(instance.bundles)
        # Compute predicted path 
        predictedPath = smart_greedy_predictor(
            trainedModel, instance, solution, bundle, i, CAPA
        )
        # Update solution with the predicted path
        updateCost = update_solution!(
            solution, instance, bundle, predictedPath; sorted=true
        )
        totalCost += updateCost
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i * 100 / B))% ")
    end
    println()
    return totalCost
end

###########################################################################################
##################################   Training   ###########################################         
###########################################################################################

# TODO
# Train data : an instance and a solution
# Test data : pertub the instance afew times (3-5), solve it again globally and extract sub-instances from them 
# Smaller scopes : France-Brazil, Spain-Hungary, France-Turkey 

# TODO : add the gap to the corresponding full solutions of the different test instances

# TODO : add batch size > 1 ?

function train_smart_greedy_predictor!(
    model::Chain,
    instance::Instance,
    solution::Solution,
    testInstances::Vector{Instance},
    testSolutions::Vector{Solution};
    nEpochs::Int=25,
)
    @info "Training model for Smart Greedy prediction"
    # Generating train data 
    print("Generating train data... ")
    trainBundles = instance.bundles
    trainData = create_dataset(instance, solution)
    trainPaths = solution.bundlePaths
    println("Done")
    # Generating test data 
    print("Generating test data... ")
    testBundles = [instance.bundles for instance in testInstances]
    testData = [
        create_dataset(instance, solution) for
        (instance, solution) in zip(testInstances, testSolutions)
    ]
    testPaths = [solution.bundlePaths for solution in testSolutions]
    println("Done")
    # Regularized predictor for Fenchel Young loss
    reg_path_predictor = PerturbedMultiplicative(path_predictor; ε=0.1, nb_samples=10)
    fenchel_loss = FenchelYoungLoss(reg_path_predictor)
    function train_loss(i, b, f, p)
        return fenchel_loss(model(f), p; instance=i, bundle=b)
    end
    # Loss Optimizer
    opt_state = Flux.setup(Flux.Adam(0.01), model)
    # Logs
    trainLosses, testLosses = Float64[], Vector{Float64}[]
    # Training loop
    for e in 1:nEpochs
        @info "Starting Epoch $e"
        # Computing mean losses for history
        meanTrainLoss = mean(
            train_loss(instance, b, f, p) for
            (b, f, p) in zip(trainBundles, trainData, trainPaths)
        )
        push!(trainLosses, meanTrainLoss)
        println("Train loss : $meanTrainLoss")
        meanTestLoss = [
            mean(train_loss(inst, b, f, p) for (b, f, p) in zip(buns, datas, paths)) for
            (inst, buns, datas, paths) in
            zip(testInstances, testBundles, testData, testPaths)
        ]
        push!(testLosses, meanTestLoss)
        println("Test losses : $meanTestLoss")
        # Doing one epoch of stochastic gradient descent
        bunIdxs, B = shuffle(idx(trainBundles)), length(trainBundles)
        percentIdx = ceil(Int, B / 100)
        for (i, bIdx) in enumerate(bunIdxs)
            bundle, features, path = trainBundles[bIdx], trainData[bIdx], trainPaths[bIdx]
            # Computing loss gradient on data point
            val, grad = Flux.withgradient(model) do model
                fenchel_loss(model(features), path; instance=instance, bundle=bundle)
            end
            # Detect loss of Inf or NaN. Print a warning, and then skip update!
            if !isfinite(val) || !all(isfinite.(grad))
                @warn "loss or gradient is not finite, skipping update" epoch i val grad bIdx
                continue
            end
            # Update the model with the gradient
            Flux.update!(opt_state, model, grad)
            i % 10 == 0 && print("|")
            i % percentIdx == 0 && print(" $(round(Int, i*100/B))% ")
        end
        println()
    end
    return trainLosses, valLosses
end
