# Train the statistical model on a solution (or multiple solutions ?)

# Create the dataset to train the statistical model on from a solution
# Dataset : length(bundles) x length(arcs) x length(features) matrix
function create_dataset(instance::Instance, solution::Solution)
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

# Smart Greedy heuristic function
# Nearly the same as greedy but instaed of update cost matrix we have the inference of the statistical model

function smart_greedy_insertion()
    #
end

# TODO : add trained predictor to the arguments
function smart_greedy!(solution::Solution, instance::Instance)
    #
end