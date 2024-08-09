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
        timeSpaceGraph.currentCost[src(arc), dst(arc)] *= costFactor
    end
end

# Adding variables

function add_variables!(
    model::Model, neighborhood::Symbol, instance::Instance, bundles::Vector{Bundle}
)
    travelTimeGraph, timeSpaceGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Variable x[b, a] in {0, 1} indicate if bundle b uses arc a in the travel time graph
    arcs = [(src(arc), dst(arc)) for arc in edges(travelTimeGraph.graph)]
    @variable(model, x[idx(bundles), arcs], Bin)
    if neighborhood == :attract || neighborhood == :reduce
        # Variable z[b] in {0, 1} indicate if bundle b uses old or new path
        @variable(model, z[[bundle.idx for bundle in bundles]], Bin)
    end
    # Varible tau_a indicate the number of transport units used on arc a in the time space graph
    arcs = [(src(arc), dst(arc)) for arc in timeSpaceGraph.commonArcs]
    @variable(model, tau[arc in arcs], Int)
end

# Adding constraints

# TODO : think about the following
# Mis-using neighborhoods functions can lead to new neighborhoods
# If you can give any vector of bundles, than by slecting the bundles of a two shared node neighborhood and doing it the single plant way, we have another nieghborhood
# can be done by changing the nieghborhood name in the function called when doing the two shared node 

# Construct the matrix of right-hand side of paths constraints
function get_e_matrix(
    neighborhood::Symbol,
    bundles::Vector{Bundle},
    TTGraph::TravelTimeGraph,
    src::Int,
    dst::Int,
)
    I = repeat(idx(bundles); outer=2)
    J = vcat(TTGraph.bundleSrc[idx(bundles)], TTGraph.bundleDst[idx(bundles)])
    V = vcat(ones(length(bundles)), -1 * ones(length(bundles)))
    if neighborhood == :two_shared_node
        if !has_vertex(TTGraph.graph, src) || !has_vertex(TTGraph.graph, dst)
            @warn "$neighborhood : src or dst is unknown. Switching to full paths for those bundles."
        else
            J = repeat([src, dst]; inner=length(bundles))
        end
    end
    return sparse(I, J, V)
end

# Add path constraints on the travel time graph to the model
function add_path_constraints!(
    model::Model,
    TTGraph::TravelTimeGraph,
    bundles::Vector{Bundle},
    e::SparseMatrixCSC{Float64,Int},
)
    incMatrix, x = incidence_matrix(TTGraph.graph), model[:x]
    # Is the incicdence matrix constructed by iterating the same way as edges ? Seems yes from the documentation
    @constraint(
        model,
        path[b in idx(bundles)],
        sum(incMatrix[:, a] * x[b, arc] for (a, arc) in enumerate(edges(TTGraph.graph))) .==
            e[b, :]
    )
end

# Generate an attract path for arc src-dst and bundle
function generate_attract_path(
    instance::Instance, solution::Solution, bundle::Bundle, src::Int, dst::Int
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Update cost matrix 
    update_lb_cost_matrix!(solution, TTGraph, TSGraph, bundle; giant=true)
    # Compute path from bundleSrc to src and from dst to bundleDst
    bSrc, bDst = TTGraph.bundleSrc[bundle.idx], TTGraph.bundleDst[bundle.idx]
    return vcat(shortest_path(TTGraph, bSrc, src), shortest_path(TTGraph, dst, bDst))
end

# Generate a reduce path for arc src-dst and bundle
function generate_reduce_path(
    instance::Instance, solution::Solution, bundle::Bundle, src::Int, dst::Int
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Update cost matrix 
    update_lb_cost_matrix!(solution, TTGraph, TSGraph, bundle; giant=true)
    TTGraph.costMatrix[src, dst] = INFINITY
    # Compute path from bundleSrc to src and from dst to bundleDst
    bSrc, bDst = TTGraph.bundleSrc[bundle.idx], TTGraph.bundleDst[bundle.idx]
    return shortest_path(TTGraph, bSrc, bDst)
end

# Generate new paths for the attract or reduce neighborhood
function generate_new_paths(
    neighborhood::Symbol,
    instance::Instance,
    solution::Solution,
    bundles::Vector{Bundle},
    src::Int,
    dst::Int,
)
    # If attract neighborhood and the edge is known
    if neighborhood == :attarct
        if has_edge(instance.travelTimeGraph.graph, src, dst)
            return [
                generate_attract_path(instance, solution, bundle, src, dst) for
                bundle in bundles
            ]
        else
            @warn "$neighborhood : src-dst arc is unknown. Switching to reduce path generation."
        end
    end
    # Default case (chosen or not) is reduce
    return [
        generate_reduce_path(instance, solution, bundle, src, dst) for bundle in bundles
    ]
end

# Adds equality constraints for the old and new path formulation
function add_old_new_path_constraints!(
    model::Model,
    bundles::Vector{Bundle},
    oldPaths::Vector{Vector{Int}},
    newPaths::Vector{Vector{Int}},
)
    x, z = model[:x], model[:z]
    # oldPathIndex, newPathIndex = Tuple{Int,Tuple{Int,Int}}[], Tuple{Int,Tuple{Int,Int}}[]
    # for (bundle, oldPath, newPath) in zip(bundles, oldPaths, newPaths)
    #     for arc in partition(oldPath, 2, 1)
    #         push!(oldPathIndex, (bundle.idx, arc))
    #     end
    #     for arc in partition(newPath, 2, 1)
    #         push!(newPathIndex, (bundle.idx, arc))
    #     end
    #     # Because both paths start and end at the desired nodes, we don't have to constrain the other arcs to zero
    # end
    # TODO : check whether this is possible !
    oldPathIndex = [
        (bundle.idx, arc) for (bundle, oldPath) in zip(bundles, oldPaths),
        arc in partition(oldPath, 2, 1)
    ]
    @constraint(model, oldPaths[(b, a) in oldPathIndex], 1 - z[b] == x[b, a])
    newPathIndex = [
        (bundle.idx, arc) for (bundle, newPath) in zip(bundles, newPaths),
        arc in partition(newPath, 2, 1)
    ]
    @constraint(model, newPaths[(b, a) in newPathIndex], z[b] == x[b, a])
end

# Initialize the packing expression as sparse matrix with space used and tau variables
function init_packing_expr(model::Model, TSGraph::TimeSpaceGraph, solution::Solution)
    I = [src(arc) for arc in TSGraph.commonArcs]
    J = [dst(arc) for arc in TSGraph.commonArcs]
    # E, tau = AffExpr[], model[:tau]
    tau, bins, netArcs = model[:tau], solution.bins, TSGraph.networkArcs
    # for arc in TSGraph.commonArcs
    #     # src, dst = src(arc), dst(arc)
    #     capacity = TSGraph.networkArcs[src(arc), dst(arc)].capacity
    #     push!(
    #         E,
    #         AffExpr(
    #             sum(bin.load for bin in solution.bins[src(arc), dst(arc)]),
    #             tau[src(arc), dst(arc)] => -capacity,
    #         ),
    #     )
    #     # push!(E, expr)
    # end
    E = [
        AffExpr(
            sum(bin.load for bin in bins[src(arc), dst(arc)]; init=0.0),
            tau[src(arc), dst(arc)] => -netArcs[src(arc), dst(arc)].capacity,
        ) for arc in TSGraph.commonArcs
    ]
    return sparse(I, J, E)
end

# Add path variables (after projection) with order volume coeffs to packing expressions 
function complete_packing_expr!(
    expr::SparseMatrixCSC{AffExpr,Int}, instance::Instance, bundles::Vector{Bundle}
)
    x, TTGraph, TSGraph = model[:x], instance.travelTimeGraph, instance.timeSpaceGraph
    for bundle in bundles
        for order in bundle.orders, arc in TSGraph.commonArcs
            src, dst, volume = src(arc), dst(arc), order.volume
            # Projecting back on the travel time graph
            ttSrc, ttDst = travel_time_projector(TTGraph, TSGraph, src, dst, order)
            # Checking the arc is for the bundle
            (ttSrc == -1 || ttDst == -1) || continue
            # Add the corresponding bundle variable and order volume to the expression
            add_to_expression!(expr[src, dst], x[bundle.idx, (ttSrc, ttDst)], volume)
        end
    end
end

# Add all relaxed packing constraints on shared arc of the time space graph
function add_packing_constraints!(
    model::Model, instance::Instance, bundles::Vector{Bundle}, solution::Solution
)
    TSGraph = instance.timeSpaceGraph
    packing_expr = init_packing_expr(model, TSGraph, solution)
    complete_packing_expr!(packing_expr, instance, bundles)
    @constraint(
        model, packing[arc in TSGraph.commonArcs], packing_expr[src(arc), dst(arc)] <= 0
    )
end

# Add all constraints needed for the specified neighborhood
function add_constraints!(
    model::Model,
    neighborhood::Symbol,
    instance::Instance,
    solution::Solution,
    bundles::Vector{Bundle},
    src::Int=-1,
    dst::Int=-1,
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Path constraints on the travel time graph
    e = get_e_matrix(neighborhood, bundles, TTGraph, src, dst)
    add_path_constraints!(model, TTGraph, bundles, e)
    if neighborhood == :attract || neighborhood == :reduce
        oldPaths = solution.bundlePaths[idx(bundles)]
        newPaths = generate_new_paths(neighborhood, instance, solution, bundles, src, dst)
        add_old_new_path_constraints!(model, bundles, oldPaths, newPaths)
    end
    # Relaxed packing constraint on the time space graph
    return add_packing_constraints!(model, instance, bundles, solution)
end

# Constructing the objective

# Check if the arc is a direct or outsource one
function is_direct_outsource(travelTimeGraph::TravelTimeGraph, arc::Edge)
    arcData = travelTimeGraph.networkArcs[src(arc), dst(arc)]
    return arcData.type == :direct || arcData.type == :outsource
end

# Check whether the computation of cost is needed for the bundle on this arc
function is_bundle_on_arc(travelTimeGraph::TravelTimeGraph, arc::Edge, bundle::Bundle)
    return travelTimeGraph.bundleSrc[bundle.idx] == src(arc)
end

# TODO : this can be optimized by doing the same thing as update_cost_matrix because too many costs computed
# Computes direct and outsource cost
function milp_travel_time_arc_cost(
    TTGraph::TravelTimeGraph, TSGraph::TimeSpaceGraph, bundles::Vector{Bundle}
)
    I, J, V, sol = Int[], Int[], Float64[], Solution(TTGraph, TSGraph, bundles)
    for (a, arc) in enumerate(edges(TTGraph.graph))
        # If the arc is not direct or outsource, cost is 0 (handled by tau variables)
        !is_direct_outsource(TTGraph, arc) && continue
        # If the arc is of no concern for the bundles involved, cost is 0
        arcBundles = filter(bun -> is_bundle_on_arc(TTGraph, arc, bun), bundles)
        length(arcBundles) == 0 && continue
        # Otherwise, computing giant container for direct and linear for outsource
        append!(I, idx(arcBundles))
        append!(J, fill(a, length(arcBundles)))
        # With empty solution no need to put use_bins=false
        arcCosts = [
            arc_lb_update_cost(
                sol, TTGraph, TSGraph, bundle, src(arc), dst(arc); current_cost=true
            ) for bundle in arcBundles
        ]
        append!(V, arcCosts)
    end
    return sparse(I, J, V)
end

# Sums the current cost of shared timed arcs and pre-computed surect and outsource arcs
function add_objective!(model::Model, instance::Instance, bundles::Vector{Bundle})
    x, tau = model[:x], model[:tau]
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    x_cost = milp_travel_time_arc_cost(TTGraph, TSGraph, bundles)
    @objective(
        model,
        Min,
        sum(
            TSGraph.currentCost[src(arc), dst(arc)] .* tau[(src(arc), dst(arc))] for
            arc in TSGraph.commonArcs
        ) + sum(x_cost[:, a] .* x[:, arc] for (a, arc) in enumerate(edges(TTGraph.graph)))
    )
end

# Getting the solution

# Transform an incidence vector into an Edge
function vect_to_edge(vect::Vector{Int})
    return Edge(findfirst(isequal(-1), vect), findfirst(isequal(1), vect))
end

# Extract a vector of edges from a solution vector 
function extract_arcs_from_vector(
    bundleArcVector::Vector{Float64}, TTGraph::TravelTimeGraph
)
    usedArcIdxs = findall(x -> x > EPS, bundleArcVector)
    # using it to get incidence vectors
    usedArcVects = incidence_matrix(TTGraph.graph)[usedArcIdxs]
    # constructing list of edges
    return [vect_to_edge(arcVect) for arcVect in usedArcVects]
end

# Construct a path from a list of arcs
function get_path_from_arcs(
    bundle::Bundle, TTGraph::TravelTimeGraph, pathArcs::Vector{Edge}
)
    # constructing actual path
    idxFirst = findfirst(a -> src(a) == TTGraph.bundleSrc[bundle.idx], pathArcs)
    path = [src(pathArcs[idxFirst]), dst(pathArcs[idxFirst])]
    while path[end] != TTGraph.bundleDst[bundle.idx]
        nextEdge = findfirst(a -> src(a) == path[end], pathArcs)
        push!(path, dst(pathArcs[nextEdge]))
    end
    return path
end

function get_paths(model::Model, TTGraph::TravelTimeGraph, bundles::Vector{Bundle})
    # getting x variable value
    bundleArcMatrix = value.(model[:x])
    paths = Vector{Vector{Int}}()
    for bundle in bundles
        # finding the non zero values to indicate edges used
        bundleArcVector = bundleArcMatrix[bundle.idx, :]
        usedArcs = extract_arcs_from_vector(bundleArcVector, TTGraph)
        push!(paths, get_path_from_arcs(bundle, TTGraph, usedArcs))
    end
    return paths
end

# Selecting a plant or a common arc

function select_random_plant(instance::Instance)
    TTGraph = instance.travelTimeGraph
    return rand(
        filter(node -> TTGraph.networkNodes[node].type == :plant, TTGraph.commonNodes)
    )
end

function select_common_arc(instance::Instance)
    TTGraph = instance.travelTimeGraph
    return rand(filter(arc -> !is_direct_outsource(TTGraph, arc), edges(TTGraph.graph)))
end

function get_lns_bundles_to_update()
    # TODO : adapt to each perturbation    
end
