# Training utils

# Transforms a solution into into a dataset B points
# Each points is made of features and a true path for each bundle 

# Start with simple features to see if it works and than try with more complex ones

# Static features refers to features independant of the current solution
# Dynamic refers to features dependant of the solution

# First objective : is to replay the solving of an instance but much faster 
# Second objective : is to generalize to instance not seen but close (a few modifications on the instance) 
# Later : get a stochastic-aware predictor of optimal paths 

# TODO : put return types directly to Float32 ?

###########################################################################################
##############################   Features utils   #########################################
###########################################################################################

# Already done by a function in Flux if i'm not mistaken
function normalize_features()
    # TODO
end

# Shortcuts all have the same features for now
function shortcut_feature(nFeatures::Int)
    return zeros(nFeatures)
end

###########################################################################################
##############################   Instance features   ######################################
###########################################################################################

# Global features common to all bundles of the instance

function arc_static_features(TTGraph::TravelTimeGraph, arcSrc::Int, arcDst::Int)
    arcData = TTGraph.networkArcs[arcSrc, arcDst]
    srcData = TTGraph.networkNodes[arcSrc]
    dstData = TTGraph.networkNodes[arcDst]
    return [
        arcData.distance,
        arcData.travelTime,
        arcData.unitCost,
        arcData.carbonCost,
        srcData.volumeCost,
        dstData.volumeCost,
        arcData.isCommon,
        arcData.isLinear,
        arcData.type == :direct,
        arcData.type == :outsource,
        arcData.type == :croos_plat,
        arcData.type == :delivery,
        arcData.type == :oversea,
        arcData.type == :port_transport,
        TTGraph.stepToDel[arcSrc],
        TTGraph.stepToDel[arcDst],
    ]
end

# Compute common static (aka solution state independant) features among bundles
# Distance / travel time / unit cost / carbon cost / src node cost / dst node cost
# + is common / is linear / type as one-hot / src step to del / dst step to del 
function common_static_features(instance::Instance)
    TTGraph = instance.travelTimeGraph
    nColumns = ne(TTGraph.graph)
    nFeatures = 16
    features = zeros(nFeatures, nColumns)
    for (i, arc) in enumerate(edges(TTGraph.graph))
        arcInfo = TTGraph.networkArcs[arc.src, arc.dst]
        # Arc properties
        arcFeatures = if arcInfo.type == :shortcut
            shortcut_feature(nFeatures)
        else
            arc_static_features(TTGraph, arc.src, arc.dst)
        end
        # Updating matrix 
        features[:, i] = arcFeatures
    end
    return features
end

###########################################################################################
###########################   Bundle static features   ####################################
###########################################################################################

# TODO 
# if size >= 2
# Add quantiles of commodity size
# Quantiles are to be computed for the whole instance 
# To use preferably on the filtered instance because quantiles may be too far aparts
# end

# Bundle features independant of the solution

function direct_delivery_distance(TTGraph::TravelTimeGraph, bundle::Bundle)
    for (aSrc, aDst) in TTGraph.bundleArcs[bundle.idx]
        TTGraph.costMatrix[aSrc, aDst] = TTGraph.networkArcs[aSrc, aDst].distance
    end
    bSrc, bDst = TTGraph.bundleSrc[bundle.idx], TTGraph.bundleDst[bundle.idx]
    return shortest_path(TTGraph, bSrc, bDst)[2]
end

function commodities_features(commodities::Vector{Commodity}, CAPA::Vector{Int})
    if length(commodities) == 0
        return zeros(9)
    end
    totVol, N = sum(c -> c.size, commodities), length(commodities)
    return [
        sum(c -> c.stockCost, commodities),
        minimum(c -> c.size, commodities),
        maximum(c -> c.size, commodities),
        totVol,
        N,
        totVol / N,
        tentative_first_fit(arcInfo, commodities, CAPA),
        ceil(totVol / arcInfo.capacity),
        totVol / arcInfo.capacity,
    ]
end

# Compute static features for each bundle
# Direct distance + stock cost / min / max / sum / count / mean / BP units / GC units / LC units of each order
function bundle_static_features(instance::Instance, bundle::Bundle, CAPA::Vector{Int})
    TTGraph = instance.travelTimeGraph
    nColumns = ne(TTGraph.graph)
    nFeatures = 1 + 8 * instance.timeHorizon
    features = zeros(nFeatures, nColumns)
    for (i, arc) in enumerate(edges(TTGraph.graph))
        arcInfo = TTGraph.networkArcs[arc.src, arc.dst]
        # Completing orders not here by empty commodity vectors
        allContents = [Commodity[] for _ in 1:(instance.timeHorizon)]
        for order in bundle.orders
            allContents[order.deliveryDate] = order.content
        end
        # Arc properties
        arcFeatures = if arcInfo.type == :shortcut
            shortcut_feature(nFeatures)
        else
            vcat(
                direct_delivery_distance(TTGraph, bundle),
                commodities_features(content, CAPA) for content in allContents
            )
        end
        features[:, i] = arcFeatures
    end
    return features
end

###########################################################################################
##########################   Bundle dynamic features   ####################################
###########################################################################################

# Bundle features dependant of the solution

# WARNING
# This must be a precomputed state so that at training time it doesn't depend on the previous path predicted

# The greedy / lower bound insertion cost can be a pretty good proxy for the compatibility of a bundle with an arc
function arc_cost_features(
    inst::Instance, sol::Solution, bun::Bundle, aSrc::Int, aDst::Int, CAPA::Vector{Int}
)
    TTG, TSG = inst.travelTimeGraph, inst.timeSpaceGraph
    return [
        arc_update_cost(sol, TTG, TSG, bun, aSrc, aDst, CAPA; sorted=true),
        arc_lb_update_cost(sol, TTG, TSG, bun, aSrc, aDst; giant=true),
        arc_lb_update_cost(sol, TTG, TSG, bun, aSrc, aDst; use_bins=false),
    ]
end

function arc_utilization_features(solution::Solution, aSrc::Int, aDst::Int)
    if aSrc == -1 || aDst == -1
        return zeros(5)
    end
    totCapa = sum(bin -> bin.load, solution.bins[tsSrc, tsDst])
    return [
        length(solution.bins[aSrc, aDst]),
        maximum(bin -> bin.capacity, solution.bins[aSrc, aDst]),
        minimum(bin -> bin.capacity, solution.bins[aSrc, aDst]),
        totCapa,
        totCapa / length(solution.bins[aSrc, aDst]),
    ]
end

# Compute dynamic (aka solution state dependant) features for each bundle
function bundle_dynamic_features(
    instance::Instance, solution::Solution, bundle::Bundle, it::Int, CAPA::Vector{Int}
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    nColumns = ne(TTGraph.graph)
    nFeatures = 4 + 5 * instance.timeHorizon
    features = zeros(nFeatures, nColumns)
    for (i, arc) in enumerate(edges(TTGraph.graph))
        arcInfo = TTGraph.networkArcs[arc.src, arc.dst]
        # Projecting arc for all possible delivery date 
        projections = [(-1, -1) for _ in 1:(instance.timeHorizon)]
        for order in bundle.orders
            projections[order.deliveryDate] = time_space_projector(
                TTGraph, TSGraph, arc.src, arc.dst, order
            )
        end
        # Arc properties
        arcFeatures = if arcInfo.type == :shortcut
            shortcut_feature(nFeatures)
        else
            vcat(
                arc_cost_features(instance, solution, bundle, arc.src, arc.dst, CAPA),
                it / length(instance.bundles),
                arc_utilization_features(solution, tsSrc, tsDst) for
                (tsSrc, tsDst) in projections
            )
        end
        features[:, i] = arcFeatures
    end
    return features
end

###########################################################################################
#############################   Statistical model   #######################################
###########################################################################################

# Create and Train the statistical model

function GLM(nFeatures::Int)
    @info "Creating Generalized Linear Model with $(nFeatures + 1) parameters"
    return Chain(Dense(nFeatures => 1; bias=true), vec)
end

function MLP(nFeatures::Int)
    @info "Creating Multi Layer Perceptron with 2 hidden layers and $(nFeatures * 64 + 64 * 32 + 32) total parameters"
    return Chain(Dense(nFeatures => 64, relu), Dense(64 => 32, relu), Dense(32 => 1), vec)
end

# Computes the shortest path given by the cost prediction theta
function predicted_shortest_path(theta::Vector{Float64}; instance::Instance, bundle::Bundle)
    TTGraph = instance.travelTimeGraph
    for (i, arc) in enumerate(edges(TTGraph.graph))
        arcInfo = TTGraph.networkArcs[arc.src, arc.dst]
        arcCost = if arcInfo.type == :shortcut
            EPS
        else
            theta[i]
        end
        # Updating cost
        TTGraph.costMatrix[arc.src, arc.dst] = arcCost
    end
    bunSrc = TTGraph.bundleSrc[bundle.idx]
    bunDst = TTGraph.bundleDst[bundle.idx]
    return shortest_path(TTGraph.graph, bunSrc, bunDst)
end

# Converts a shortest path to a vector fo arc usage (1 if used, 0 otherwise)
function shortest_path_to_vector(path::Vector{Int}, instance::Instance)
    TTGraph = instance.travelTimeGraph
    arcUsage = zeros(non_shortcut_arcs(instance))
    arcPath = [aSrcDst for aSrcDst in partition(path, 2, 1)]
    i = 1
    for arc in edges(TTGraph.graph)
        arcInfo = TTGraph.networkArcs[arc.src, arc.dst]
        # Skipping shortcuts
        arcInfo.type == :shortcut && continue
        # Updating usage
        if (arc.src, arc.dst) in arcPath
            arcUsage[i] = 1.0
        end
        # Updating index
        i += 1
    end
    return arcUsage
end

# Predictor to be used by the pipeline
function path_predictor(theta::Vector{Float64}; instance::Instance, bundle::Bundle)
    # Compute the shortest path given the model output
    predictedPath = predicted_shortest_path(theta; instance, bundle)
    # Tranform it in the form of a vector of edges boolean
    pathVector = shortest_path_to_vector(predictedPath, instance)
    return pathVector
end

function save_model(model::Chain, name::String)
    model_state = Flux.state(model)
    return jldsave("$(name)_parameters.jld2"; model_state)
end

function load_model!(model::Chain, name::String)
    model_state = JLD2.load("$(name)_parameters.jld2", "model_state")
    return Flux.loadmodel!(model, model_state)
end
