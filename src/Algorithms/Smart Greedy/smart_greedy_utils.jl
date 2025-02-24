# Training utils

# Transforms a solution into into a dataset B points
# Each points is made of features and a true path for each bundle 

# Start with simple features to see if it works and than try with more complex ones

# Static features refers to features independant of the current solution
# Dynamic refers to features dependant of the solution

# First objective : is to replay the solving of an instance but much faster 
# Second objective : is to generalize to instance not seen but close (a few modifications on the instance) 

# TODO : add non_shortcu_arcs into the TTGraph structure ?

###########################################################################################
##############################   Features utils   #########################################
###########################################################################################

# Already done by a function in Flux if i'm not mistaken
function normalize_features()
    # TODO
end

function non_shortcut_arcs(instance::Instance)
    TTGraph = instance.travelTimeGraph
    TTArcs = instance.travelTimeGraph.networkArcs
    return count(e -> TTArcs[e.src, e.dst].type != :shortcut, edges(TTGraph.graph))
end

###########################################################################################
##############################   Instance features   ######################################
###########################################################################################

# TODO : put return types directly to Float32 ?

# Global features common to all bundles of the instance

function arc_core_features(TTGraph::TravelTimeGraph, arcSrc::Int, arcDst::Int)
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
    ]
end

function arc_other_features(TTGraph::TravelTimeGraph, arcSrc::Int, arcDst::Int)::Float64
    arcData = TTGraph.networkArcs[arcSrc, arcDst]
    return [
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
# Size regulates the number of fetures to gather 
# - 0 : none
# - 1 : distance / travel time / unit cost / carbon cost / src node cost / dst node cost
# - 2 : those above + is common / is linear / type as one-hot / src step to del / dst step to del 
function common_static_features(instance::Instance; size::Int=1)
    TTGraph = instance.travelTimeGraph
    nColumns = non_shortcut_arcs(instance)
    # Nothing to compute if size = 0
    size == 0 && return zeros(0, nColumns)
    nFeatures = size >= 1 ? 6 : 16
    features = zeros(nFeatures, nColumns)
    i = 1
    for arc in edges(TTGraph.graph)
        arcInfo = TTGraph.networkArcs[arc.src, arc.dst]
        # Skipping shortcuts
        arcInfo.type == :shortcut && continue
        # Arc properties
        features[1:6, i] = arc_core_features(TTGraph, arc.src, arc.dst)
        # If extended features, computed the other properties
        if size > 1
            features[7:16, i] = arc_other_features(TTGraph, arc.src, arc.dst)
        end
        # Updating index
        i += 1
    end
    return features
end

###########################################################################################
###########################   Bundle static features   ####################################
###########################################################################################

# Bundle features independant of the solution

function direct_delivery_distance(TTGraph::TravelTimeGraph, bundle::Bundle)
    for (aSrc, aDst) in TTGraph.bundleArcs[bundle.idx]
        TTGraph.costMatrix[aSrc, aDst] = TTGraph.networkArcs[aSrc, aDst].distance
    end
    bSrc, bDst = TTGraph.bundleSrc[bundle.idx], TTGraph.bundleDst[bundle.idx]
    return shortest_path(TTGraph, bSrc, bDst)[2]
end

function commodities_features(commodities::Vector{Commodity})
    totVol, N = sum(c -> c.size, commodities), length(commodities)
    return [
        sum(c -> c.stockCost, commodities),
        minimum(c -> c.size, commodities),
        maximum(c -> c.size, commodities),
        totVol,
        N,
        totVol / N,
        tentative_first_fit(arcInfo, commodities, Int[]),
        ceil(totVol / arcInfo.capacity),
        totVol / arcInfo.capacity,
    ]
end

# Compute static features for each bundle
# Size regulates the number of fetures to gather 
# - 0 : none
# - 1 : distance direct delivery / total stock cost / min / max / sum / count / mean / ffd units / giant container units / linear units of concatenated orders
# - 2 : same as above and adding the same for each order
function bundle_static_features(instance::Instance, bundle::Bundle; size::Int=1)
    TTGraph = instance.travelTimeGraph
    nColumns = non_shortcut_arcs(instance)
    # Nothing to compute if size = 0
    size == 0 && return zeros(0, nColumns)
    nFeatures = size >= 1 ? 10 : 10 + 8 * instance.timeHorizon
    features = zeros(nFeatures, nColumns)
    i = 1
    for arc in edges(TTGraph.graph)
        arcInfo = TTGraph.networkArcs[arc.src, arc.dst]
        # Skipping shortcuts
        arcInfo.type == :shortcut && continue
        # Direct delivery distance
        features[1, i] = direct_delivery_distance(TTGraph, bundle)
        # Stats on concatenation of orders
        allCommodities = vcat(order.content for order in bundle.orders)
        features[2:10, i] = commodities_features(allCommodities)
        # If extended features, computed the properties per order
        if size >= 1
            for order in bundle.orders
                delDate = order.deliveryDate
                firstIdx, lastIdx = 10 + 8 * (delDate - 1) + 1, 10 + 8 * delDate
                features[firstIdx:lastIdx, i] = commodities_features(order.content)
                if size >= 2
                    # Add quantiles of commodity size
                end
            end
        end
        # Updating index
        i += 1
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
function arc_cost_features(inst::Instance, sol::Solution, bun::Bundle, aSrc::Int, aDst::Int)
    TTG, TSG = inst.travelTimeGraph, inst.timeSpaceGraph
    return [
        arc_update_cost(sol, TTG, TSG, bun, aSrc, aDst, Int[]; sorted=true),
        arc_lb_update_cost(sol, TTG, TSG, bun, aSrc, aDst; giant=true),
        arc_lb_update_cost(sol, TTG, TSG, bun, aSrc, aDst; use_bins=false),
    ]
end

function arc_utilization_features(solution::Solution, aSrc::Int, aDst::Int)
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
    instance::Instance, solution::Solution, bundle::Bundle; size::Int=1
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    nColumns = non_shortcut_arcs(instance)
    nFeatures = size >= 1 ? 4 : 9
    features = zeros(nFeatures, nColumns)
    i = 1
    for arc in edges(TTGraph.graph)
        arcInfo = TTGraph.networkArcs[arc.src, arc.dst]
        # Skipping shortcuts
        arcInfo.type == :shortcut && continue
        # Greedy insertion cost
        features[1:3, i] .= arc_cost_features(instance, solution, bundle, arc.src, arc.dst)
        # Iteration of algorithm
        features[4, i] = bundle.idx / length(instance.bundles)
        # Current arc utilization
        if size >= 1
            concatFeatures = zeros(5)
            for order in bundle.orders
                tsSrc, tsDst = time_space_projector(
                    TTGraph, TSGraph, arc.src, arc.dst, order
                )
                concatFeatures += arc_utilization_features(solution, tsSrc, tsDst)
            end
            features[5:9, i] .= concatFeatures / length(bundle.orders)
            if size >= 2
                # Add features for each arc of each time step
            end
        end
        # Updating index
        i += 1
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
    return Chain(
        Dense(nFeatures => 64, relu),
        Dropout(0.5),
        Dense(64 => 32, relu),
        Dense(32 => 1),
        vec,
    )
end

# Computes the shortest path given by the cost prediction theta
function predicted_shortest_path(theta::Vector{Float64}; instance::Instance, bundle::Bundle)
    TTGraph = instance.travelTimeGraph
    i = 1
    for arc in edges(TTGraph.graph)
        arcInfo = TTGraph.networkArcs[arc.src, arc.dst]
        # Skipping shortcuts
        arcInfo.type == :shortcut && continue
        # Updating cost
        TTGraph.costMatrix[arc.src, arc.dst] = theta[i]
        # Updating index
        i += 1
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
