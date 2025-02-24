# Train the statistical model on a solution (or multiple solutions ?)

# We start by doing the code for training on a single instance to be able to replay it multiple times faster with slight modifications

###########################################################################################
##################################   Dataset   ###########################################         
###########################################################################################

# Transform an instance, a solution and a bundle into a matrix of features per arc
function smart_greedy_features(
    instance::Instance, solution::Solution, bundle::Bundle; size::Int=1
)
    return vcat(
        common_static_features(instance; size=size),
        bundle_static_features(instance, bundle; size=size),
        bundle_dynamic_features(instance, solution, bundle; size=size),
    )
end

# Create the dataset associated to an instance and a solution
# Dataset : length(bundles) vector of length(features) x length(arcs) matrix
function create_dataset(instance::Instance, solution::Solution; size::Int=1)
    dataset = Vector{Matrix{Float64}}(undef, length(instance.bundles))
    # True paths are already known
    truePaths = deepcopy(solution.bundlePaths)
    # Deepcopy the solution (with my own method for more efficiency) to modify it without modifying the original
    sol = my_deepcopy(solution)
    # Sorting bundles by reverse order of greedy insertion
    sortedBundleIdxs = sortperm(instance.bundles; by=bun -> bun.maxPackSize)
    # For each bundle, reverting the solution to the state before its insertion and computing arc features
    for bundleIdx in sortedBundleIdxs
        bundle = instance.bundles[bundleIdx]
        bundlePath = sol.bundlePaths[bundleIdx]
        # Removing bundle from solution
        update_solution!(sol, instance, bundle, bundlePath; remove=true, sorted=true)
        # Computing bundle features
        bundleFeatures = smart_greedy_features(instance, sol, bundle; size=size)
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
    model::Chain, instance::Instance, solution::Solution, bundle::Bundle; size::Int
)
    # Encode the instance and bundle features
    features = smart_greedy_features(instance, solution, bundle; size=size)
    # Give the features to the model
    theta = model(features)
    # Compute the shortest path given the model output
    predictedPath = predicted_shortest_path(theta; instance, bundle)
    # Tranform it in the form of a vector of edges boolean
    pathVector = shortest_path_to_vector(predictedPath, instance)
    return pathVector
end

# Smart Greedy heuristic function
# Nearly the same as greedy but instaed of update cost matrix we have the inference of the statistical model
function smart_greedy!(
    solution::Solution, instance::Instance, trainedModel::Chain; size::Int
)
    totalCost = 0.0
    print("Smart Greedy introduction progress : ")
    percentIdx = ceil(Int, length(sortedBundleIdxs) / 100)
    # Compute all paths with the predicted costs
    for bundle in instance.bundles
        # Compute predicted path 
        predictedPath = smart_greedy_predictor(
            trainedModel, instance, solution, bundle; size=size
        )
        # Update solution with the predicted path
        updateCost = update_solution!(
            solution, instance, bundle, predictedPath; sorted=true
        )
        totalCost += updateCost
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i * 100 / length(sortedBundleIdxs)))% ")
    end
    println()
    return totalCost
end

###########################################################################################
##################################   Training   ###########################################         
###########################################################################################

function mean_train_loss()
    return mean(
        train_loss(instance, b, f, p) for
        (b, f, p) in zip(trainBundles, trainData, trainPaths)
    )
end

function mean_test_loss()
    #
end

function gap()
    #
end

function batch_data()
    #
end

function train_smart_greedy_predictor()
    # Regularized predictor and Fenchel Young loss
    reg_path_predictor = PerturbedMultiplicative(path_predictor; ε=0.1, nb_samples=10)
    fenchel_loss = FenchelYoungLoss(reg_path_predictor)
    function train_loss(i, b, f, p)
        return fenchel_loss(model(f), p; instance=i, bundle=b)
    end
    # Optimizer and Options
    opt_state = Flux.setup(Flux.Adam(0.01), model)
    nEpochs, batchSize = 25, 32
    trainLosses, testLosses, gapHistory = Float64[], Float64[], Float64[]
    # Divide instance bundles into 80% train and 20% test
    trainBundles, trainData, trainPaths, testBundles, testData, testPaths = divide_dataset(
        allData, allPaths
    )
    nBatch = ceil(Int, length(trainBundles) / batchSize)
    # Training loop
    for _ in 1:nEpochs
        # Computing mean losses for history
        meanTrainLoss = mean(
            train_loss(instance, b, f, p) for
            (b, f, p) in zip(trainBundles, trainData, trainPaths)
        )
        push!(trainLosses, meanTrainLoss)
        meanTestLoss = mean(
            train_loss(instance, b, f, p) for
            (b, f, p) in zip(testBundles, testData, testPaths)
        )
        push!(testLosses, meanTestLoss)
        # Computing mean gap for history (recalculating full solution)
        fullSolution = Solution(instance)
        smart_greedy!(fullSolution, instance, model)
        gap = (compute_cost(instance, fullSolution) - trueCost) / trueCost * 100
        push!(gapHistory, gap)
        # Doing one epoch of mini-batch stochastic gradient descent
        bunIdxs = shuffle(idx(trainBundles))
        for bi in 1:nBatch
            bStart = (bi - 1) * batchSize + 1
            bEnd = min(bi * batchSize, length(trainBundles))
            data = [
                (trainBundles[b], trainData[b], trainPaths[b]) for b in bunIdxs[bStart:bEnd]
            ]
            batchGrad = Vector{Float64}[]
            for (bun, feat, path) in data
                # Computing loss gradient on batch
                val, grads = Flux.withgradient(model) do m
                    fenchel_loss(m(feat), path; instance=instance, bundle=bun)
                end
                # Detect loss of Inf or NaN. Print a warning, and then skip update!
                if !isfinite(val)
                    @warn "loss is $val on bundle $(bun.idx)" epoch
                    continue
                end
                batchGrad += grads / length(data)
            end
            # Update the model with the gradients
            Flux.update!(opt_state, model, grads[1])
        end
    end
    return trainLosses, valLosses, gapHistory
end
