# Utils function for the large neighborhood search

# For arcs in the time-space network :
#     Update the current cost with the following mechanism :
#         Compute an actual volume cost : volume_cost = (unit_cost * nb_of_units) / total_volume_in_units
#         Compute the updated unit cost : unit cost = unit_capacity * volume_cost
# Use this new costs in all the other heuristics

function slope_scaling_cost_update!(timeSpaceGraph::TimeSpaceGraph)
    for arc in edges(timeSpaceGraph.graph)
        arcData = timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        # No update for linear arcs
        arcData.isLinear && continue
        # Total volume on arc
        arcVolume = sum(arcData.capacity - bin.availableCapacity for bin in arcBins)
        # All arc bins
        arcBins = timeSpaceGraph.bins[src(arc), dst(arc)]
        # Updating current cost
        baseCost = (arcData.unitCost + arcData.carbonCost)
        costFactor = length(arcBins) * arcData.capacity / arcVolume
        timeSpaceGraph.currentCost[src(arc), dst(arc)] = baseCost * costFactor
    end
end

# TODO : e is a matrix B x V, construct it sparse, depend whether all bundles have same source and dest or just same source or none
function get_e_matrix() end

# Add path constraints on the travel time graph to the model
function add_path_constraints!(
    model::Model,
    travelTimeGraph::TravelTimeGraph,
    bundles::Vector{Bundle},
    e::SparseMatrixCSC{Int,Int},
)
    incidence_matrix = incidence_matrix(travelTimeGraph.graph)
    bundlesIndexes = [bundle.idx for bundle in bundles]
    x = model[:x]
    @constraint(model, path[b in bundlesIndexes], incidence_matrix * x[b, :] .== e[b, :])
end

# Initialize the packing expression as sparse matrix with space used and tau variables
function init_packing_expr(model::Model, timeSpaceGraph::TimeSpaceGraph)
    I, J, E, tau = Int[], Int[], AffExpr[], model[:tau]
    for arc in timeSpaceGraph.commonArcs
        expr = AffExpr(
            sum(timeSpaceGraph.binLoads[src(arc), dst(arc)]),
            tau[arc] => -timeSpaceGraph.networkArcs[src(arc), dst(arc)].capacity,
        )
        push!(I, src(arc))
        push!(J, dst(arc))
        push!(E, expr)
    end
    return sparse(I, J, E)
end

# Add all relaxed packing constraints on shared arc of the time space graph
function add_packing_constraints!(
    model::Model,
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    bundles::Vector{Bundle},
)
    x = model[:x]
    packing_expr = init_packing_expr(model, timeSpaceGraph)
    for bundle in bundles
        for order in bundle.orders
            for arc in timeSpaceGraph.commonArcs
                # Projecting back on the travel time graph
                ttSrc, ttDst = travel_time_projector(
                    travelTimeGraph, timeSpaceGraph, src(arc), dst(arc), order
                )
                # Checking the arc is for the bundle
                (ttSrc == -1 || ttDst == -1) || continue
                # Add the corresponding bundle variable and order volume to the expression
                add_to_expression!(
                    packing_expr[src(arc), dst(arc)],
                    x[bundle.idx, (ttSrc, ttDst)],
                    order.volume,
                )
            end
        end
    end
    @constraint(
        model,
        packing[arc in timeSpaceGraph.commonArcs],
        packing_expr[src(arc), dst(arc)] <= 0
    )
end

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
    cost_matrix = zeros(length(bundles), ne(TTGraph.graph))
    for (a, arc) in enumerate(edges(TTGraph.graph))
        # If the arc is not direct or outsource, cost is 0 (handled by tau variables)
        if !is_direct_outsource(TTGraph, arc)
            cost_matrix[:, a] .= 0
            continue
        end
        # Otherwise, computing giant container for direct and linear for outsource
        for (b, bundle) in enumerate(bundles)
            cost_matrix[b, a] = get_arc_milp_cost(
                TTGraph, TSGraph, bundle, src(arc), dst(arc);
            )
        end
    end
    return cost_matrix
end

# Sums the current cost of shared timed arcs and pre-computed surect and outsource arcs
function get_milp_objective(
    model::Model,
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    bundles::Vector{Bundle},
)
    x, tau = model[:x], model[:tau]
    return sum(
        timeSpaceGraph.currentCost[src(arc), dst(arc)] * tau[arc] for
        arc in timeSpaceGraph.commonArcs
    ) + sum(
        get_direct_outsource_cost(
            travelTimeGraph::TravelTimeGraph,
            timeSpaceGraph::TimeSpaceGraph,
            bundles::Vector{Bundle},
        ) .* x,
    )
end

function create_neighborhood_milp(
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    bundles::Vector{Bundle},
)
    model = Model(HiGHS.Optimizer)

    # Variable x[b, a] in {0, 1} indicate if bundle b uses arc a in the travel time graph
    @variable(
        model, x[[bundle.idx for bundle in bundles], edges(travelTimeGraph.graph)], Bin
    )
    # Varible tau_a indicate the number of transport units used on arc a in the time space graph
    @variable(model, tau[timeSpaceGraph.commonArcs], Int)

    # Path constraints on the travel time graph
    e = get_e_matrix()
    add_path_constraints!(model, travelTimeGraph, bundles, e)
    # Relaxed packing constraint on the time space graph
    add_packing_constraints!(model, travelTimeGraph, timeSpaceGraph, bundles)

    # Objective
    @objective(
        model, Min, get_milp_objective(model, travelTimeGraph, timeSpaceGraph, bundles)
    )
    # Returning the constructed model
    return model
end

# TODO : add a function to add constraints fot he path formulation ? or directly a new milp ?

function solve_milp()
    # Options
    # Solving
    optimize!(model)
    status = termination_status(model)
    @assert status == MOI.OPTIMAL || status == MOI.FEASIBLE_POINT

    # Getting the solution
    # Returning the solution
end