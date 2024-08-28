# Training utils

# Cut a solution into a training dataset

# Own deepcopy function to remove runtime dispatch with deepcopy
function my_deepcopy(solution::Solution, instance::Instance)
    newSol = Solution(instance)
    for bundle in instance.bundles
        append!(newSol.bundlePaths[bundle.idx], solution.bundlePaths[bundle.idx])
    end
    for node in solution.bundlesOnNode
        append!(newSol.bundlesOnNode[node], solution.bundlesOnNode[node])
    end
    # Efficient iteration over sparse matrix
    rows = rowvals(solution.bins)
    bins = nonzeros(solution.bins)
    for j in 1:size(A, 2)
        for i in nzrange(solution.bins, j)
            append!(newSol.bins[rows[i]], bins[i])
        end
    end
    return newSol
end

# Compute common static (aka solution state independant) features among bundles 
function compute_global_static_features(instance::Instance, solution::Solution)
    TTGraph = instance.travelTimeGraph
    nFeatures = 1
    features = zeros(ne(TTGraph.graph), nFeatures)
    for (i, arc) in enumerate(edges(TTGraph.graph))
        # TODO : that's where you need notes from Max
    end
    return features
end

# Compute static features for each bundle
function compute_bundle_static_features(
    instance::Instance, solution::Solution, bundle::Bundle
)
    TTGraph = instance.travelTimeGraph
    nFeatures = 1
    features = zeros(ne(TTGraph.graph), nFeatures)
    for (i, arc) in enumerate(edges(TTGraph.graph))
        # TODO : that's where you need notes from Max
    end
    return features
end

# Compute dynamic (aka solution state dependant) features for each bundle
function compute_bundle_dynamic_features(
    instance::Instance, solution::Solution, bundle::Bundle
)
    TTGraph = instance.travelTimeGraph
    nFeatures = 1
    features = zeros(ne(TTGraph.graph), nFeatures)
    for (i, arc) in enumerate(edges(TTGraph.graph))
        # TODO : that's where you need notes from Max
    end
    return features
end

# Create and Train the statistical model

function create_glm(nFatures::Int)
    return Chain(Dense(nFatures => 1; bias=true), vec)
end

# TODO : dijkstra in our case
function easy_problem()
end

# Store its parameters to just read it upon inference calling

# Infrence utils

# Load parameters of statistical model

# Update cost matrix with values predicted

# Compute shortest path for bundle insertion
