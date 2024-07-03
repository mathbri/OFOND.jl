# Utils function for the large neighborhood search

# For arcs in the time-space network :
#     Update the current cost with the following mechanism :
#         Compute an actual volume cost : volume_cost = (unit_cost * nb_of_units) / total_volume_in_units
#         Compute the updated unit cost : unit cost = unit_capacity * volume_cost
# Use this new costs in all the other heuristics

function slope_scaling_cost_update!(timeSpaceGraph::TimeSpaceGraph, solution::Solution)
    for arc in edges(timeSpaceGraph.graph)
        arcData = timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        # No update for linear arcs
        arcData.isLinear && continue
        # Total volume on arc
        arcBins = solution.bins[src(arc), dst(arc)]
        arcVolume = sum(bin.load for bin in arcBins)
        # Updating current cost
        timeSpaceGraph.currentCost[src(arc), dst(arc)] = arcData.unitCost
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
    if neighborhood == :attract_reduce
        # Variable z[b] in {0, 1} indicate if bundle b uses old or new path
        @variable(model, z[[bundle.idx for bundle in bundles]], Bin)
    end
    # Varible tau_a indicate the number of transport units used on arc a in the time space graph
    arcs = [(src(arc), dst(arc)) for arc in timeSpaceGraph.commonArcs]
    @variable(model, tau[arc in arcs], Int)
end

# Adding constraints

# TODO : think about the following
# If you can give any vector of bundles, than by slecting the bundles of a two shared node neighborhood and doing it the single plant way, we have another nieghborhood
# can be done by changing the nieghborhood name in the function called when doing the two shared node 

# Construct the matrix of right-hand side of paths constraints
function get_e_matrix(
    neighborhood::Symbol,
    bundles::Vector{Bundle},
    TTGraph::TravelTimeGraph,
    src::Int=-1,
    dst::Int=-1,
)
    I = repeat(idx(bundles); outer=2)
    J = vcat(TTGraph.bundleSrc[idx(bundles)], TTGraph.bundleDst[idx(bundles)])
    if neighborhood == :two_shared_node && src != -1 && dst != -1
        J = vcat(repeat(src, length(bundles)), repeat(dst, length(bundles)))
    end
    V = vcat(ones(length(bundles)), -1 * ones(length(bundles)))
    return sparse(I, J, V)
end

# Add path constraints on the travel time graph to the model
function add_path_constraints!(
    model::Model,
    TTGraph::TravelTimeGraph,
    bundles::Vector{Bundle},
    e::SparseMatrixCSC{Float64,Int},
)
    incidence_matrix = incidence_matrix(TTGraph.graph)
    x = model[:x]
    # Is the incicdence matrix constructed by iterating the same way as edges ? Seems yes from the documentation
    @constraint(model, path[b in idx(bundles)], incidence_matrix * x[b, :] .== e[b, :])
end

# Adds equality constraints for the old and new path formulation
function add_old_new_path_constraints!(
    model::Model,
    bundles::Vector{Bundle},
    oldPaths::Vector{Vector{Int}},
    newPaths::Vector{Vector{Int}},
)
    x, z = model[:x], model[:z]
    for (bundle, oldPath, newPath) in zip(bundles, oldPaths, newPaths)
        for arc in partition(oldPath, 2, 1)
            @constraint(model, 1 - z[bundle.idx] == x[bundle.idx, arc])
        end
        for arc in partition(newPath, 2, 1)
            @constraint(model, z[bundle.idx] == x[bundle.idx, arc])
        end
        # Because both paths start and end at the desired nodes, we don't have to constrain the other arcs to zero
    end
end

# Initialize the packing expression as sparse matrix with space used and tau variables
function init_packing_expr(model::Model, TSGraph::TimeSpaceGraph, solution::Solution)
    I = [src(arc) for arc in TSGraph.commonArcs]
    J = [dst(arc) for arc in TSGraph.commonArcs]
    E, tau = AffExpr[], model[:tau]
    for arc in TSGraph.commonArcs
        src, dst = src(arc), dst(arc)
        capacity = TSGraph.networkArcs[src, dst].capacity
        expr = AffExpr(
            sum(bin.load for bin in solution.bins[src, dst]), tau[src, dst] => -capacity
        )
        push!(E, expr)
    end
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
# TODO : separate attract_reduce to attract and reduce
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
    e = get_e_matrix(:single_plant, bundles, TTGraph, src, dst)
    add_path_constraints!(model, TTGraph, bundles, e)
    if neighborhood == :attract_reduce
        # TODO : is random the best option ?
        oldPaths = solution.bundlePaths[idx(bundles)]
        newPaths = generate_new_paths()
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

# Compute cost as giant container for direct and linear for others
function get_arc_milp_cost(
    TTGraph::TravelTimeGraph, TSGraph::TimeSpaceGraph, bundle::Bundle, src::Int, dst::Int
)
    arcData = TTGraph.networkArcs[src, dst]
    arcBundleCost = EPS
    for order in bundle.orders
        # Getting time space projection
        timedSrc, timedDst = time_space_projector(
            TTGraph, TSGraph, src, dst, order.deliveryDate
        )
        # Node volume cost 
        arcBundleCost += get_order_node_com_cost(TTGraph, src, dst, order)
        # Arc transport cost 
        arcBundleCost +=
            get_lb_transport_units(order, arcData) * TSGraph.currentCost[timedSrc, timedDst]
    end
    return arcBundleCost
end

# Computes direct and outsource cost
function get_direct_outsource_cost(
    TTGraph::TravelTimeGraph, TSGraph::TimeSpaceGraph, bundles::Vector{Bundle}
)
    I, J, V = Int[], Int[], Float64[]
    for (a, arc) in enumerate(edges(TTGraph.graph))
        # If the arc is not direct or outsource, cost is 0 (handled by tau variables)
        !is_direct_outsource(TTGraph, arc) && continue
        # Otherwise, computing giant container for direct and linear for outsource
        for (b, bundle) in enumerate(bundles)
            push!(I, b)
            push!(J, a)
            push!(V, get_arc_milp_cost(TTGraph, TSGraph, bundle, src(arc), dst(arc)))
        end
    end
    return sparse(I, J, V)
end

# Sums the current cost of shared timed arcs and pre-computed surect and outsource arcs
function add_objective!(model::Model, instance::Instance, bundles::Vector{Bundle})
    x, tau = model[:x], model[:tau]
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    path_cost = get_direct_outsource_cost(TTGraph, TSGraph, bundles)
    @objective(model, Min, sum(TSGraph.currentCost .* tau) + sum(path_cost .* x))
end

# Getting the solution

function get_used_arc_from_arc_vector(bundleArcVector::Vector{Float64}, incidence_matrix)
    usedArcIdxs = findall(x -> x > EPS, bundleArcVector)
    # using it to get incidence vectors
    usedArcVects = incidence_matrix[usedArcIdxs]
    # constructing list of edges
    usedArcs = Vector{Edge}()
    for arcVect in usedArcVects
        source = findfirst(x -> x == -1, arcVect)
        dest = findfirst(x -> x == 1, arcVect)
        push!(usedArcs, Edge(source, dest))
    end
    return usedArcs
end

function get_path_from_arcs(bundle::Bundle, usedArcs::Vector{Edge})
    # constructing actual path
    firstEdge = findfirst(a -> src(a) == bundle.supplier, usedArcs)
    path = Int[src(usedArcs[firstEdge]), dst(usedArcs[firstEdge])]
    while path[end] != bundle.customer
        nextEdge = findfirst(a -> src(a) == path[end], usedArcs)
        push!(path, dst(usedArcs[nextEdge]))
    end
    return path
end

function get_paths(model::Model, bundles::Vector{Bundle}, incidence_matrix)
    # getting x variable value
    arcMatrix = value.(model[:x])
    paths = Vector{Vector{Int}}()
    for bundle in bundles
        # finding the non zero values to indicate edges used
        bundleArcVector = arcMatrix[bundle.idx, :]
        usedArcs = get_used_arc_from_arc_vector(bundleArcVector, incidence_matrix)
        push!(paths, get_path_from_arcs(bundle, usedArcs))
    end
    return paths
end

function select_random_plant(instance::Instance)
    TTGraph = instance.travelTimeGraph
    return rand(
        filter(node -> TTGraph.networkNodes[node].type == :plant, TTGraph.commonNodes)
    )
end

function select_common_network_arc(instance::Instance)
    TTGraph = instance.travelTimeGraph
    return rand(filter(arc -> !is_direct_outsource(TTGraph, arc), edges(TTGraph.graph)))
end

# TODO : look back into the article to see how they do it
# Maybe for us lb greddy would be fast and efficient ?
function generate_new_paths() end