# Training utils

# Cut a solution into a training dataset

# TODO : this a not computable at inference time, this needs to be transformed as bundle dependant, meaning its computed for the current solution seen by the bundle
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

# TODO : may be a need to remove shortcut deletion in shortest path computation
# Computes the shortest path given by the cost prediction theta
function predicted_shortest_path(theta::Vector{Float64}, instance::Instance, bundle::Bundle)
    for (i, edge) in enumerate(edges(instance.travelTimeGraph.graph))
        instance.travelTimeGraph.costMatrix[edge.src, edge.dst] = theta[i]
    end
    bunSrc = instance.travelTimeGraph.bundleSrc[bundle.idx]
    bunDst = instance.travelTimeGraph.bundleDst[bundle.idx]
    return shortest_path(instance.travelTimeGraph.graph, bunSrc, bunDst)
end

# Store its parameters to just read it upon inference calling

# Infrence utils

# Load parameters of statistical model

# Update cost matrix with values predicted

# Compute shortest path for bundle insertion
