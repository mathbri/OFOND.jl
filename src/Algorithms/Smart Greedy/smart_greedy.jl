# Train the statistical model on a solution (or multiple solutions ?)

# Create the dataset associated to an instance and a solution
# Dataset : length(bundles) x length(arcs) x length(features) matrix
function create_dataset_sample(instance::Instance, solution::Solution)
    nFeatures = 1
    TTGraph = instance.travelTimeGraph
    inputFeatures = zeros(length(instance.bundles), ne(TTGraph.graph), nFeatures)
    truePaths = deepcopy(solution.bundlePaths)
    # Deepcopy the solution (with my own method for more efficiency)
    # TODO : check the runtime dispatch is gone with my_deepcopy
    sol = my_deepcopy(solution)
    # Sorting bundles by reverse order of greedy insertion
    sortedBundleIdxs = sortperm(instance.bundles; by=bun -> bun.maxPackSize)
    commonStaticFeatures = compute_global_static_features(instance, sol)
    # For each bundle, reverting the solution to the state before its insertion and computing arc features
    for bundleIdx in sortedBundleIdxs
        bundle = instance.bundles[bundleIdx]
        bundlePath = sol.bundlePaths[bundleIdx]
        # Removing bundle from solution
        update_solution!(sol, instance, bundle, bundlePath; remove=true, sorted=true)
        # Computing bundle insertion features
        bundleStaticFeatures = compute_bundle_static_features(instance, sol, bundle)
        bundleDynamicFeatures = compute_bundle_dynamic_features(instance, sol, bundle)
        inputFeatures[bundleIdx, :, :] = hcat(
            commonStaticFeatures, bundleStaticFeatures, bundleDynamicFeatures
        )
    end
    return inputFeatures, truePaths
end

# TODO : may be a need to chage this functions to only modify a pre-existing dataset structure
# Create the dataset to train the statistical model based on an instance
function create_dataset(instance::Instance)
    nTrain, nVal = 10, 5
    TTGraph = instance.travelTimeGraph
    dataset = zeros(nTrain + nVal, length(instance.bundles), ne(TTGraph.graph), nFeatures)
    # Computes nTrain + nVal solutions with the LNS heuristic
    for i in 1:(nTrain + nVal)
        solution = Solution(instance)
        lns_heuristic!(solution, instance; timeLimit=10, lsTimeLimit=10)
        # For each solution, we create a dataset sample
        dataset[i, :, :, :] = create_dataset_sample(instance, solution)
    end
    return dataset, nTrain
end

function train_glm()
    regularizedPredictor = PerturbedMultiplicative(easy_problem; ε=0.1, nb_samples=10)
    loss = FenchelYoungLoss(regularizedPredictor)
    flux_loss(x, y) = loss(φ_w(x.features), y.value; instance=x)
    # Optimizer
    opt = Adam()
    # Training loop
    nEpochs = 25
    trainLosses, valLosses, gapHistory = Float64[], Float64[], Float64[]
    for _ in 1:nb_epochs
        l = mean(flux_loss(x, y) for (x, y) in data_train)
        l_test = mean(flux_loss(x, y) for (x, y) in data_val)
        Y_pred = [pipeline(x) for x in X_val]
        values = [evaluate_solution(y, x) for (x, y) in zip(X_val, Y_pred)]
        V = mean((v_pred - v) / v * 100 for (v_pred, v) in zip(values, ground_truth_obj))
        push!(training_losses, l)
        push!(val_losses, l_test)
        push!(objective_gap_history, V)

        Flux.train!(flux_loss, Flux.params(φ_w), data_train, opt)
    end
end

# Smart Greedy heuristic function
# Nearly the same as greedy but instaed of update cost matrix we have the inference of the statistical model

function smart_greedy!(solution::Solution, instance::Instance, trained_glm::Chain)
    totalCost = 0.0
    print("Smart Greedy introduction progress : ")
    percentIdx = ceil(Int, length(sortedBundleIdxs) / 100)
    # Compute all paths with the predicted costs
    for bundle in instance.bundles
        # Compute features
        bundleFreatures = hcat(
            compute_global_static_features(instance, solution),
            compute_bundle_static_features(instance, solution, bundle),
            compute_bundle_dynamic_features(instance, solution, bundle),
        )
        # Predict arc costs
        predictedCosts = trained_glm(bundleFreatures)
        # Compute shortest path with it
        predictedPath = predicted_shortest_path(predictedCosts, instance, bundle)
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

function pipeline(instance::Instance, trained_glm::Chain)
    # Create an empty solution
    solution = Solution(instance)
    smart_greedy!(solution, instance, trained_glm)
    return solution
end

# Evaluate dataset with glm
function evaluate_dataset_with_glm()
    initial_pred = [pipeline(x) for x in X_val]
    initial_obj = [evaluate_solution(y, x) for (x, y) in zip(X_val, initial_pred)]
    ground_truth_obj = [evaluate_solution(y, x) for (x, y) in data_val]

    initial_average_gap = mean((initial_obj .- ground_truth_obj) ./ ground_truth_obj .* 100)
    @info "Initial gap ≃ $(round(initial_average_gap; digits=2))%"
end