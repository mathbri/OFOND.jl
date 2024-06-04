# Functions used for lower bound computation

function lb_transport_units(
    solution::Solution,
    TSGraph::TimeSpaceGraph,
    timedSrc::Int,
    timedDst::Int,
    order::Order;
    use_bins::Bool,
    giant::Bool,
)
    arcData = TSGraph.networkArcs[timedSrc, timedDst]
    # Transport cost 
    orderTrucks = get_lb_transport_units(order, arcData)
    # If we take into account the current solution
    if use_bins
        bins = solution.bins[timedSrc, timedDst]
        # If the arc is not empty, computing space left in last giant container approx and removing it from the cost 
        if length(bins) > 0
            truckSpaceLeft = sum(bin.capacity for bin in bins) / arcData.capacity
            orderTrucks = max(0, orderTrucks - truckSpaceLeft)
        end
    end
    (giant && !arcData.isLinear) && (orderTrucks = ceil(orderTrucks))
    return orderTrucks
end

function arc_lb_update_cost(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
    use_bins::Bool=true,
    current_cost::Bool=false,
    giant::Bool=false,
)
    # If the arc is forbidden for the bundle, returning INF
    is_forbidden(TTGraph, src, dst, bundle) && return INFINITY
    # Otherwise, computing the new cost
    arcBundleCost = EPS
    for order in bundle.orders
        # Getting time space projection
        timedSrc, timedDst = time_space_projector(
            TTGraph, TSGraph, src, dst, order.deliveryDate
        )
        # Node volume cost 
        arcBundleCost += volume_stock_cost(TTGraph, src, dst, order)
        # Arc transport cost 
        arcBundleCost +=
            lb_transport_units(
                solution, TSGraph, timedSrc, timedDst, order; use_bins=use_bins, giant=giant
            ) * transport_cost(TSGraph, timedSrc, timedDst; current_cost=current_cost)
    end
    return arcBundleCost
end

# Updating cost matrix on the travel time graph for a specific bundle 
function update_lb_cost_matrix!(
    solution::Solution,
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    bundle::Bundle;
    use_bins::Bool=true,
    current_cost::Bool=false,
    giant::Bool=false,
)
    # Iterating through outneighbors of the start nodes and common nodes
    for src in
        vcat(get_all_start_nodes(travelTimeGraph, bundle), travelTimeGraph.commonNodes)
        for dst in outneighbors(travelTimeGraph, src)
            # If the arc doesn't need an update, skipping
            is_update_candidate(TTGraph, src, dst, bundle) || continue
            # Otherwise, computing the new cost
            travelTimeGraph.costMatrix[src, dst] = arc_lb_update_cost(
                solution,
                travelTimeGraph,
                timeSpaceGraph,
                bundle,
                src,
                dst;
                use_bins=use_bins,
                current_cost=current_cost,
                giant=giant,
            )
        end
    end
end

# TODO
function lower_bound_filtering!(instance::Instance, solution::Solution)
    # solution is supposed to be one from lower bound heuristic
    # (or run lower bound heuristic first)
    # two mode : aggressive or not 
    # aggressive : all bundle taking direct paths are filtered from instance
    # not aggressive : all bundle taking direct paths and BP lower bound is reached for orders are filtered from instance
    # use milp packing for order bp precomputation ?
end