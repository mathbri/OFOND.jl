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

# TODO : At least a function to build the milp based on the bundles
# Could be good idea to have a function if there is one point (plant neighbor) and two nodes (two node neighbor or attract reduce neighbor)

# TODO : finish this function and make sur the indices and all corresponds
# define packing variable only on the consolidated arcs
# define direct and outsource bundle costs
# add all corresponding arguments : bundles concerned, travel time graph, time space graph, start end nodes, ...
# detect whether the path and packing constraints don't have any variables inside ? unlickily because path constraints on all the travel time graph...

function create_neighborhood_milp()
    # model = Model(optimizer_with_attributes(() -> Gurobi.Optimizer(GRB_ENV), "OutputFlag" => 0))
    model = Model(HiGHS.Optimizer)

    # Variables
    nBundles, nArcsTT, nArcsTS = length(bundles),
    ne(travelTimeGraph.graph),
    ne(timeSpaceGraph.graph)
    # Variable x[b, a] in {0, 1} indicate if bundle b uses arc a in the travel time graph
    @variable(model, x[1:nBundles, 1:nArcsTT], Bin)
    # Varible tau_a indicate the number of transport units used on arc a in the time space graph
    @variable(model, tau[1:nArcsTS], Int)

    # Constraints
    # TODO : missing the node argument in here
    # Path constraints on the travel time graph
    incidence_matrix = incidence_matrix(travelTimeGraph.graph)
    @constraint(model, path[b=1:nBundles], incidence_matrix * x[b, :] .== startEndVector[b])
    # Relaxed packing constraint on the time space graph
    for arc in edges(timeSpaceGraph.graph)
        expr = AffExpr(timeSpaceGraph.bins[a], tau[a] => -timeSpaceGraph.unitCapacity[a])
        for bundle in bundles
            travelTimeSources, travelTimesDests = travel_time_projector(
                travelTimeGraph, timeSpaceGraph, arc, bundle
            )
            for (idxO, order) in enumerate(bundle.orders)
                src, dst = travelTimeSources[idxO], travelTimesDests[idxO]
                src != -1 &&
                    dst != -1 &&
                    add_to_expression!(expr, x[bundle.idx, (src, dst)], order.volume)
            end
        end
        @constraint(model, packing[arc], expr <= 0)
    end

    # Objective
    @objective(
        model,
        Min,
        sum(timeSpaceGraph.currentCost[a] * tau[a] for a in 1:nArcsTS) +
            sum(directOrOutsourceCost[b, a] * x[b, a] for b in 1:nBundles, a in 1:nArcsTT)
    )

    # Returning the constructed model
    return model
end

function solve_milp()
    # Options
    # Solving
    optimize!(model)
    status = termination_status(model)
    @assert status == MOI.OPTIMAL || status == MOI.FEASIBLE_POINT

    # Getting the solution
    # Returning the solution
end