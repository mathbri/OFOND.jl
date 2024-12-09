# Utils function for the large neighborhood search

# For arcs in the time-space network :
#     Update the current cost with the following mechanism :
#         Compute an actual volume cost : volume_cost = (unit_cost * nb_of_units) / total_volume_in_units
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
        costFactor = length(arcBins) * arcData.capacity / arcVolume
        # Limiting cost factor to 2
        costFactor = min(2.0, costFactor)
        # Allowing cost decrease for common arcs
        if arcData.type in COMMON_ARC_TYPES
            costFactor -= 0.5
        end
        timeSpaceGraph.currentCost[src(arc), dst(arc)] *= costFactor
    end
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
    # println("New loads : $loads")
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

# TODO : if no attract path possible propose direct ?
# or filtering bundles for which new paths don't make sense ?
# proposing a reduce path meaning a classical lower bound insertion path

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
    oldPaths = solution.bundlePaths
    loads = map(bins -> 0, solution.bins)
    bundleIdxs = idx(instance.bundles)
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

# TODO : think about the following
# Mis-using neighborhoods functions can lead to new neighborhoods
# If you can give any vector of bundles, than by slecting the bundles of a two shared node neighborhood and doing it the single plant way, we have another nieghborhood
# can be done by changing the nieghborhood name in the function called when doing the two shared node 

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

# Not tested
function select_random_plant(instance::Instance)
    TTGraph = instance.travelTimeGraph
    return rand(findall(node -> node.type == :plant, TTGraph.networkNodes))
end

# TODO : stack bundles associated with plants until the cost threshold is reached ?
# function select_random_plant(instance::Instance, solution::Solution, costThreshold::Float64)
#     src, dst, allPertBunIdxs, estimRemCost = -1, -1, Int[], 0.0
#     TTGraph = instance.travelTimeGraph
#     plants = findall(node -> node.type == :plant, TTGraph.networkNodes)
#     # Going through all plants in random order to select one
#     for plant in shuffle(plants)
#         pertBunIdxs = get_bundles_to_update(instance, solution, plant)
#         # If no bundle for this plant, skipping to another directly
#         length(pertBunIdxs) == 0 && continue
#         # Computing estimated cost
#         pertBundles = instance.bundles[pertBunIdxs]
#         oldPaths = get_lns_paths_to_update(:single_plant, solution, pertBundles, src, dst)
#         estimRemCost += sum(
#             bundle_estimated_removal_cost(bundle, oldPath, instance, solution) for
#             (bundle, oldPath) in zip(pertBundles, oldPaths)
#         )
#         # Adding bundles to the list of perturbed bundles
#         append!(allPertBunIdxs, pertBunIdxs)
#         # If it is suitable, breaking search and returning
#         estimRemCost > costThreshold && return src, dst, allPertBunIdxs
#     end
#     # If no plant found, returning empty vector
#     return src, dst, Int[]
# end

# Not tested
function get_shuffled_common_arcs(instance::Instance)
    TTGraph = instance.travelTimeGraph
    return shuffle(
        filter(
            arc -> TTGraph.networkArcs[src(arc), dst(arc)].type in COMMON_ARC_TYPES,
            collect(edges(TTGraph.graph)),
        ),
    )
end

# TODO : Still useful ?
# function get_lns_paths_to_update(
#     neighborhood::Symbol,
#     solution::Solution,
#     bundles::Vector{Bundle},
#     node1::Int,
#     node2::Int,
# )::Vector{Vector{Int}}
#     if neighborhood == :two_shared_node && node1 != -1 && node2 != -1
#         return get_paths_to_update(solution, bundles, node1, node2)
#     else
#         return solution.bundlePaths[idx(bundles)]
#     end
# end

#######################################################################################
# New idea to be tested
#######################################################################################

# The neighborhood only determines the bundles concerned and the potential paths for them
# Doesn't work for two node for now because need to put src and dst as arguments
# Works for single_plant, random, suppliers, attract and reduce
# POC for now

# function generate_bundle_potential_paths(
#     instance::Instance, solution::Solution, bundle::Bundle; nPaths::Int
# )
#     TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
#     # Update cost matrix 
#     update_lb_cost_matrix!(solution, TTGraph, TSGraph, bundle; use_bins=false)
#     # Compute n paths from bundleSrc to bundleDst
#     # TODO : with this setting, as all paths are independent, this generation can be done once at the beginning
#     # Even without this setting it could be done once at the beginning and updated once in a while
#     bSrc, bDst = TTGraph.bundleSrc[bundle.idx], TTGraph.bundleDst[bundle.idx]
#     yenState = yen_k_shortest_paths(
#         travelTimeGraph.graph, src, travelTimeGraph.costMatrix, nPaths; maxdist=INFINITY
#     )
#     # TODO : maybe the k shortest path generation will be the bottleneck
#     # Keeping shortcuts or ease of MILP implementation
#     return enumerate_paths(yenState)
# end

# function add_variables_paths!(
#     model::Model, instance::Instance, startSol::RelaxedSolution, nPaths::Int
# )
#     TSGraph = instance.timeSpaceGraph
#     bundleIdxs = startSol.bundleIdxs
#     # Variable p[b, k] in {0, 1} indicate if bundle b uses path k in the travel time graph
#     @variable(model, p[b in bundleIdxs, k in 1:nPaths], Bin)
#     # Varible tau_a indicate the number of transport units used on arc a in the time space graph
#     @variable(model, tau[arc in timeSpaceGraph.commonArcs], Int)
# end

# function add_path_constraints_paths!(model::Model, bundleIdxs::Vector{Int})
#     p = model[:p]
#     # 1 path needs to be chosen between all potential paths
#     @constraint(model, paths[b in bundleIdxs], sum(p[b, :]) == 1)
# end

# function complete_packing_expr_paths!(
#     model::Model,
#     expr::SparseMatrixCSC{AffExpr,Int},
#     instance::Instance,
#     bundles::Vector{Bundle},
#     potentialPaths::Vector{Vector{Vector{Int}}},
# )
#     p, TTGraph, TSGraph = model[:p], instance.travelTimeGraph, instance.timeSpaceGraph
#     # Iterating each potential paths of each bundle
#     for bundle in bundles
#         for bundlePaths in potentialPaths[bundle.idx]
#             # For each potential path
#             for (k, path) in bundlePaths
#                 # For each arc of this potential bundle path
#                 for (src, dst) in partition(path, 2, 1)
#                     # If it is not a common arc, filtering 
#                     !TTGraph.networkArcs[src, dst].isCommon && continue
#                     # Projecting arc on the time space graph for each order of the bundle
#                     for order in bundle.orders
#                         tSrc, tDst = time_space_projector(TTGraph, TSGraph, src, dst, order)
#                         # Adding the corresponding variable to the packing constraint
#                         add_to_expression!(expr[tSrc, tDst], p[bundle.idx, k], order.volume)
#                     end
#                 end
#             end
#         end
#     end
# end

# # Add all relaxed packing constraints on shared arc of the time space graph
# function add_packing_constraints_paths!(
#     model::Model,
#     instance::Instance,
#     bundles::Vector{Bundle},
#     solution::Solution,
#     potentialPaths::Vector{Vector{Vector{Int}}},
# )
#     TSGraph = instance.timeSpaceGraph
#     packing_expr = init_packing_expr(model, TSGraph, solution)
#     complete_packing_expr_paths!(model, packing_expr, instance, bundles, potentialPaths)
#     @constraint(
#         model, packing[(src, dst) in TSGraph.commonArcs], packing_expr[src, dst] <= 0
#     )
# end

# function add_constraints_paths!(
#     model::Model,
#     instance::Instance,
#     solution::Solution,
#     startSol::RelaxedSolution,
#     potentialPaths::Vector{Vector{Vector{Int}}},
# )
#     # Path constraints on the travel time graph
#     add_path_constraints_paths!(model, startSol.bundleIdxs)
#     bundles = instance.bundles[startSol.bundleIdxs]
#     # Relaxed packing constraint on the time space graph
#     return add_packing_constraints_paths!(
#         model, instance, bundles, solution, potentialPaths
#     )
# end

# # TODO : base costs can also be precomputed once at the beginning
# function milp_travel_time_path_cost(
#     TTGraph::TravelTimeGraph,
#     TSGraph::TimeSpaceGraph,
#     bundles::Vector{Bundle},
#     potentialPaths::Vector{Vector{Vector{Int}}},
# )
#     print("Creating MILP potential paths costs... ")
#     nBun, nPaths = length(potentialPaths), length(potentialPaths[1])
#     potentialCosts = [zeros(nPaths) for _ in 1:nBun]
#     for bundle in bundles
#         for bundlePaths in potentialPaths[bundle.idx]
#             for (k, path) in bundlePaths
#                 pathCost = 0.0
#                 for (src, dst) in partition(path, 2, 1)
#                     arcData = TTGraph.networkArcs[src, dst]
#                     # No cost for shortcut arcs
#                     if arcData.type == :shortcut
#                         pathCost += 1e-5
#                         continue
#                     end
#                     # Common cost is the sum for orders of volume and stock cost
#                     pathCost += sum(
#                         volume_stock_cost(TTGraph, src, dst, order) for
#                         order in bundle.orders
#                     )
#                     # Complete cost for outsource and direct arcs
#                     if arcData.type in [:outsource, :direct]
#                         for order in bundle.orders
#                             tSrc, tDst = time_space_projector(
#                                 TTGraph, TSGraph, src, dst, order
#                             )
#                             orderTrucks = get_lb_transport_units(order, arcData)
#                             pathCost +=
#                                 orderTrucks * TSGraph.currentCost[timedSrc, timedDst]
#                         end
#                     end
#                 end
#                 potentialCosts[bundle.idx][k] = pathCost
#             end
#         end
#     end
#     println("done")
#     return potentialCosts
# end

# # Sums the current cost of shared timed arcs and pre-computed surect and outsource arcs
# function add_objective_paths!(
#     model::Model,
#     instance::Instance,
#     startSol::RelaxedSolution,
#     potentialPaths::Vector{Vector{Vector{Int}}},
# )
#     p, tau = model[:p], model[:tau]
#     TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
#     bundles = instance.bundles[startSol.bundleIdxs]
#     p_cost = milp_travel_time_path_cost(TTGraph, TSGraph, bundles, potentialPaths)
#     objExpr = AffExpr()
#     for (src, dst) in TSGraph.commonArcs
#         add_to_expression!(objExpr, tau[(src, dst)], TSGraph.currentCost[src, dst])
#     end
#     for varIdx in eachindex(p)
#         bunIdx, pathIdx = varIdx
#         add_to_expression!(objExpr, p[bunIdx, pathIdx], p_cost[bunIdx][pathIdx])
#     end
#     @objective(model, Min, objExpr)
# end

# function get_paths_paths(
#     model::Model,
#     instance::Instance,
#     startSol::RelaxedSolution,
#     potentialPaths::Vector{Vector{Vector{Int}}},
# )
#     TTGraph = instance.travelTimeGraph
#     bundles = instance.bundles[startSol.bundleIdxs]
#     # getting x variable value
#     pValue = value.(model[:p])
#     paths = Vector{Vector{Int}}()
#     allArcs = collect(edges(TTGraph.graph))
#     for bundle in bundles
#         # finding the non zero value to indicate path used
#         pBundleValue = pvalue[bundle.idx, :]
#         usedPathIdx = findfirst(x -> x > 1 - 1e-3, pBundleValue)
#         bundlePath = potentialPaths[bundle.idx][usedPathIdx]
#         !is_path_admissible(TTGraph, bundlePath) &&
#             @warn "Path proposed with milp is not admissible, add elementarity constraint !" :bundle =
#                 bundle :path = join(bundlePath, "-") :nodes = join(
#                 string.(map(n -> TTGraph.networkNodes[n], bundlePath)), ", "
#             )
#         push!(paths, bundlePath)
#     end
#     return paths
# end

# bundle, arc, and so on selection unction don't need to be changed
