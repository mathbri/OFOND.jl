# Utils function for the large neighborhood search

# For arcs in the time-space network :
#     Update the current cost with the following mechanism :
#         Compute an actual bin cost : true_cost = unit_cost * (nb_of_units / ceil(total_volume_in_units) )
#         Compute the updated unit cost : unit cost = unit_capacity * volume_cost
# Use this new costs in all the other heuristics

function slope_scaling_cost_update!(timeSpaceGraph::TimeSpaceGraph, solution::Solution)
    for arc in edges(timeSpaceGraph.graph)
        arcData = timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        # Updating current cost
        timeSpaceGraph.currentCost[src(arc), dst(arc)] = arcData.unitCost
        # No scaling for linear arcs
        arcData.isLinear && continue
        # Total volume on arc
        arcBins = solution.bins[src(arc), dst(arc)]
        arcVolume = sum(bin.load for bin in arcBins; init=0)
        # No scaling for arcs with no volume
        arcVolume <= EPS && continue
        # costFactor = length(arcBins) * arcData.capacity / arcVolume
        costFactor = length(arcBins) / ceil(arcVolume / arcData.capacity)
        # Limiting cost factor to 2
        costFactor = min(2.0, costFactor)
        # Allowing cost decrease for common arcs
        if arcData.type in COMMON_ARC_TYPES
            costFactor -= 0.5
        end
        timeSpaceGraph.currentCost[src(arc), dst(arc)] *= costFactor
    end
end

function slope_scaling_cost_update!(instance::Instance, solution::Solution)
    return slope_scaling_cost_update!(instance.timeSpaceGraph, solution)
end

###########################################################################################
##############################   Perturbation creation   ##################################
###########################################################################################

function compute_loads(
    instance::Instance,
    solution::Solution,
    bundleIdxs::Vector{Int},
    oldPaths::Vector{Vector{Int}},
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Computing the current load
    loads = map(bins -> sum(bin.load for bin in bins; init=0), solution.bins)
    # println("Loads : $loads")
    # Removing the load of bundles to be modified with the neighborhood
    for (bIdx, bPath) in zip(bundleIdxs, oldPaths)
        bundle = instance.bundles[bIdx]
        # Updating the loads along the path
        for (src, dst) in partition(bPath, 2, 1)
            for order in bundle.orders
                tSrc, tDst = time_space_projector(TTGraph, TSGraph, src, dst, order)
                loads[tSrc, tDst] -= order.volume
                # println("Removed $(order.volume) from ($tSrc, $tDst)")
            end
        end
    end
    return loads
end

function arc_flow_perturbation(
    instance::Instance, solution::Solution, bundleIdxs::Vector{Int}
)
    oldPaths = solution.bundlePaths[bundleIdxs]
    loads = compute_loads(instance, solution, bundleIdxs, oldPaths)
    return Perturbation(:arc_flow, bundleIdxs, oldPaths, loads)
end

function two_shared_node_perturbation(
    instance::Instance, solution::Solution, src::Int, dst::Int
)
    # Bundle idxs are determined by the ones flowinf from src to dst 
    bundleIdxs = get_bundles_to_update(instance.travelTimeGraph, solution, src, dst)
    # Extracting old paths between src and dst
    twoNodeBundles = instance.bundles[bundleIdxs]
    oldPaths = get_paths_to_update(solution, twoNodeBundles, src, dst)
    loads = compute_loads(instance, solution, bundleIdxs, oldPaths)
    return Perturbation(:two_shared_node, bundleIdxs, src, dst, oldPaths, loads)
end

# Generate an attract path for arc src-dst and bundle
function generate_attract_path(
    instance::Instance, solution::Solution, bundle::Bundle, src::Int, dst::Int
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Compute path from bundleSrc to src and from dst to bundleDst
    bSrc, bDst = TTGraph.bundleSrc[bundle.idx], TTGraph.bundleDst[bundle.idx]
    # Update cost matrix 
    update_lb_cost_matrix!(
        solution, TTGraph, TSGraph, bundle; use_bins=true, current_cost=true
    )
    # If bDst = dst then no path and that's problematic
    secondPart = if bDst == dst
        [bDst]
    else
        shortest_path(TTGraph, dst, bDst)[1]
    end
    return vcat(shortest_path(TTGraph, bSrc, src)[1], secondPart)
end

# Generate a reduce path for arc src-dst and bundle
function generate_reduce_path(
    instance::Instance, solution::Solution, bundle::Bundle, src::Int, dst::Int
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Update cost matrix 
    update_lb_cost_matrix!(
        solution, TTGraph, TSGraph, bundle; use_bins=true, current_cost=true
    )
    TTGraph.costMatrix[src, dst] = INFINITY
    # Compute path from bundleSrc to src and from dst to bundleDst
    bSrc, bDst = TTGraph.bundleSrc[bundle.idx], TTGraph.bundleDst[bundle.idx]
    return shortest_path(TTGraph, bSrc, bDst)[1]
end

function path_flow_perturbation(instance::Instance, solution::Solution, src::Int, dst::Int)
    bundleIdxs = idx(instance.bundles)
    oldPaths = solution.bundlePaths
    bundlesOnArc = get_bundles_to_update(instance.travelTimeGraph, solution, src, dst)
    newPaths = Vector{Vector{Int}}(undef, length(solution.bundlePaths))
    # Generating reduce paths for the bundles on arc
    for bIdx in bundlesOnArc
        bundle = instance.bundles[bIdx]
        newPaths[bIdx] = generate_reduce_path(instance, solution, bundle, src, dst)
    end
    # Generating attract paths for the bundles not on arc
    TTGraph = instance.travelTimeGraph
    bundlesNotOnArc = setdiff(idx(instance.bundles), bundlesOnArc)
    for bIdx in bundlesNotOnArc
        bundle = instance.bundles[bIdx]
        bSrc, bDst = TTGraph.bundleSrc[bIdx], TTGraph.bundleDst[bIdx]
        if has_path(TTGraph.graph, bSrc, src) && has_path(TTGraph.graph, dst, bDst)
            newPaths[bIdx] = generate_attract_path(instance, solution, bundle, src, dst)
        else
            # If no attract path possible, giving another path
            newPaths[bIdx] = generate_reduce_path(instance, solution, bundle, src, dst)
        end
    end
    loads = map(bins -> 0, solution.bins)
    return Perturbation(:attract_reduce, bundleIdxs, oldPaths, newPaths, loads)
end

###########################################################################################
#########################  Perturbation bundles determination   ###########################
###########################################################################################

# Selecting bundles based on the plant they deliver
function select_bundles_by_plant(instance::Instance; maxVar::Int=MAX_MILP_VAR)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    pertBunIdxs, pertVar = Int[], length(TSGraph.commonArcs)
    plants = findall(node -> node.type == :plant, TTGraph.networkNodes)
    # Going through all plants in random order to select one
    for plant in shuffle(plants)
        bunIdxs = findall(dst -> dst == plant, TTGraph.bundleDst)
        # If no bundle for this plant, skipping to another directly
        length(bunIdxs) == 0 && continue
        # Adding bundles one by one until the maximum number is reached 
        for bIdx in shuffle(bunIdxs)
            if pertVar + length(TTGraph.bundleArcs[bIdx]) <= maxVar
                push!(pertBunIdxs, bIdx)
                pertVar += length(TTGraph.bundleArcs[bIdx])
            end
        end
        # If the number of variables is more than 90% of the limit, stopping the search
        pertVar > 0.9 * maxVar && return pertBunIdxs
    end
    # If 90% cap not reached, returning all bundles nonetheless
    return pertBunIdxs
end

# Select bundles based on the customer they come from
function select_bundles_by_supplier(instance::Instance; maxVar::Int=MAX_MILP_VAR)
    pertBunIdxs = Int[]
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    pertVar = length(TSGraph.commonArcs)
    # Getting all suppliers at index 0 (to not select multiple times the same supplier)
    suppliers = findall(node -> node.type == :supplier, TTGraph.networkNodes)
    filter!(sup -> TTGraph.stepToDel[sup] == 0, suppliers)
    # Going through all suppliers in random order to select one
    for supplier in shuffle(suppliers)
        # Getting all bundle sharing the same supplier, possibly with different start date
        supplierNode = TTGraph.networkNodes[supplier]
        bunIdxs = findall(
            bunSrc -> TTGraph.networkNodes[bunSrc] == supplierNode, TTGraph.bundleSrc
        )
        # If no bundle for this plant, skipping to another directly
        length(bunIdxs) == 0 && continue
        # Adding bundles one by one until the maximum number is reached 
        for bIdx in shuffle(bunIdxs)
            if pertVar + length(TTGraph.bundleArcs[bIdx]) <= maxVar
                push!(pertBunIdxs, bIdx)
                pertVar += length(TTGraph.bundleArcs[bIdx])
            end
        end
        # If the number of variables is more than 90% of the limit, stopping the search
        pertVar > 0.9 * maxVar && return pertBunIdxs
    end
    # If 90% cap not reached, returning all bundles nonetheless
    return pertBunIdxs
end

# Select bundles randomly
function select_random_bundles(instance::Instance; maxVar::Int=MAX_MILP_VAR)
    src, dst, pertBunIdxs = -1, -1, Int[]
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    pertVar = length(TSGraph.commonArcs)
    shuffledBundles = randperm(length(instance.bundles))
    # Going through all bundles in random order to select some
    for bIdx in shuffledBundles
        # Adding bundles one by one until the maximum number is reached 
        if pertVar + length(TTGraph.bundleArcs[bIdx]) <= maxVar
            push!(pertBunIdxs, bIdx)
            pertVar += length(TTGraph.bundleArcs[bIdx])
        elseif pertVar > 0.9 * maxVar
            # If the number of variables is more than 90% of the limit, stopping the search
            return pertBunIdxs
        end
    end
    # If 90% cap not reached, returning all bundles nonetheless
    return pertBunIdxs
end

function select_bundles_by_two_node(
    instance::Instance, solution::Solution, costThreshold::Float64
)
    src, dst, pertBunIdxs, estimRemCost = -1, -1, Int[], 0.0
    srcMax, dstMax, estimMax = -1, -1, 0.0
    TTGraph = instance.travelTimeGraph
    plantNodes = findall(x -> x.type == :plant, TTGraph.networkNodes)
    two_node_nodes = vcat(TTGraph.commonNodes, plantNodes)
    for src in shuffle(two_node_nodes), dst in shuffle(two_node_nodes)
        # If nodes are not candidate, skipping
        !are_nodes_candidate(TTGraph, src, dst) && continue
        pertBunIdxs = get_bundles_to_update(TTGraph, solution, src, dst)
        # If no bundle for these two nodes, skipping to another directly
        length(pertBunIdxs) == 0 && continue
        # Computing estimated cost
        pertBundles = instance.bundles[pertBunIdxs]
        oldPaths = get_paths_to_update(solution, pertBundles, src, dst)
        estimRemCost = sum(
            bundle_estimated_removal_cost(bundle, oldPath, instance, solution) for
            (bundle, oldPath) in zip(pertBundles, oldPaths)
        )
        # If it is suitable, breaking search and returning
        estimRemCost > costThreshold && return src, dst, pertBunIdxs
        # If it is better than the current best, saving it
        if estimRemCost > estimMax
            srcMax, dstMax, estimMax = src, dst, estimRemCost
        end
    end
    # If no two nodes found, returning maximum estimated cost found
    pertBunIdxs = get_bundles_to_update(TTGraph, solution, srcMax, dstMax)
    return srcMax, dstMax, pertBunIdxs
end

###########################################################################################
################################   Perturbation call  #####################################
###########################################################################################

function select_common_arc(instance::Instance)
    TTGraph = instance.travelTimeGraph
    arc = rand(
        filter(
            arc -> TTGraph.networkArcs[src(arc), dst(arc)].type in COMMON_ARC_TYPES,
            collect(edges(TTGraph.graph)),
        ),
    )
    return src(arc), dst(arc)
end

function get_perturbation(type::Symbol, instance::Instance, solution::Solution)
    TTGraph = instance.travelTimeGraph
    if type == :attract_reduce
        src, dst = select_common_arc(instance)
        println(
            "Common arc selected : $src -> $dst ($(TTGraph.networkNodes[src]) -> $(TTGraph.networkNodes[dst]))",
        )
        return path_flow_perturbation(instance, solution, src, dst)
    elseif type == :two_shared_node
        startCost = compute_cost(instance, solution)
        threshold = 1e-3 * startCost
        src, dst, pertBunIdxs = select_bundles_by_two_node(instance, solution, threshold)
        return two_shared_node_perturbation(instance, solution, src, dst)
    else
        # Otherwise, it is a "classic" arc flow perturbation
        pertBunIdxs = if type == :suppliers
            select_bundles_by_supplier(instance)
        elseif type == :random
            select_random_bundles(instance)
        else
            # If the type is single plant or is unknown, defaulting to single_plant
            select_bundles_by_plant(instance)
        end
        return arc_flow_perturbation(instance, solution, pertBunIdxs)
    end
end

###########################################################################################
###############################   Miscallaneous utils  ####################################
###########################################################################################

function is_outsource_direct_shortcut(TTGraph::TravelTimeGraph, src::Int, dst::Int)
    arcData = TTGraph.networkArcs[src, dst]
    return arcData.type == :outsource ||
           arcData.type == :direct ||
           arcData.type == :shortcut
end

function is_outsource_direct(TTGraph::TravelTimeGraph, src::Int, dst::Int)
    arcData = TTGraph.networkArcs[src, dst]
    return arcData.type == :outsource || arcData.type == :direct
end

# Shortcut arcs are missing from primal paths
function get_shortcut_part(TTGraph::TravelTimeGraph, bundleIdx::Int, startNode::Int)
    return collect(TTGraph.bundleSrc[bundleIdx]:-1:startNode)
end

# Not tested because not used
function select_random_plant(instance::Instance)
    TTGraph = instance.travelTimeGraph
    return rand(findall(node -> node.type == :plant, TTGraph.networkNodes))
end

# Not tested because not used
function get_shuffled_common_arcs(instance::Instance)
    TTGraph = instance.travelTimeGraph
    return shuffle(
        filter(
            arc -> TTGraph.networkArcs[src(arc), dst(arc)].type in COMMON_ARC_TYPES,
            collect(edges(TTGraph.graph)),
        ),
    )
end

function get_lns_paths_to_update(
    solution::Solution, bundles::Vector{Bundle}, perturbation::Perturbation
)
    if is_two_shared_node(perturbation)
        return get_paths_to_update(solution, bundles, perturbation.src, perturbation.dst)
    else
        return solution.bundlePaths[idx(bundles)]
    end
end

function model_with_optimizer(;
    MIPGap::Float64=0.001, timeLimit::Float64=150.0, verbose::Bool=false
)
    model = Model(HiGHS.Optimizer)
    gapFlag = "mip_rel_gap"
    # Trying to assign Gurobi
    try
        model = Model(Gurobi.Optimizer)
        gapFlag = "MIPGap"
    catch e
        # Then CPLEX
        try
            model = Model(CPLEX.Optimizer)
            gapFlag = "CPXPARAM_MIP_Tolerances_MIPGap"
        catch e
            # Fallback on HiGHS by default
        end
    end
    # Assigning common options
    set_optimizer_attribute(model, gapFlag, MIPGap)
    set_time_limit_sec(model, timeLimit)
    !verbose && set_silent(model)
    return model
end

function is_perturbation_empty(perturbation::Perturbation; verbose::Bool=false)
    if length(perturbation.bundleIdxs) == 0
        # If no bundles, aborting perturbation
        verbose && println("No bundles taken, aborting pertubation")
        return true
    end
    return false
end

function are_new_paths(
    oldPaths::Vector{Vector{Int}}, newPaths::Vector{Vector{Int}}; verbose::Bool=false
)
    if newPaths == oldPaths
        # If no bundle changed, aborting perturbation
        verbose && println("No bundle changed, aborting pertubation")
        return false
    end
    return true
end

function get_new_paths_idx(
    perturbation::Perturbation, oldPaths::Vector{Vector{Int}}, newPaths::Vector{Vector{Int}}
)
    return findall(i -> newPaths[i] != perturbation.oldPaths[i], eachindex(newPaths))
end

function save_previous_bins(
    instance::Instance,
    solution::Solution,
    bundles::Vector{Bundle},
    oldPaths::Vector{Vector{Int}},
)
    TSGraph, TTGraph = instance.timeSpaceGraph, instance.travelTimeGraph
    return save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, bundles, oldPaths)
    )
end
