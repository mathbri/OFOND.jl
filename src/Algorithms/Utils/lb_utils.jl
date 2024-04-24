# Functions used for lower bound computation

function get_order_transport_units(
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
    arcOrderTrucks = get_lb_transport_units(order, arcData)
    # If we take into account the current solution
    if use_bins
        loads = solution.binLoads[timedSrc, timedDst]
        # If the arc is not empty, computing space left in last giant container approx and removing it from the cost 
        if length(loads) > 0
            spaceLeft = sum(loads) / arcData.capacity
            arcOrderTrucks = max(0, arcOrderTrucks - spaceLeft)
        end
    end
    giant && (arcOrderTrucks = ceil(arcOrderTrucks))
    return arcOrderTrucks
end

function get_arc_lb_cost(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
    use_bins::Bool,
    current_cost::Bool,
    giant::Bool,
)
    arcData = TTGraph.networkArcs[src, dst]
    # If the arc doesn't need an update, skipping
    is_update_candidate(arcData, dst, TTGraph.bundleDst[bundle.idx]) ||
        return TTGraph.costMatrix[src, dst]
    # Otherwise, computing the new cost
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
            get_order_transport_units(
                solution, TSGraph, timedSrc, timedDst, order; use_bins=use_bins, giant=giant
            ) * get_transport_cost(TSGraph, timedSrc, timedDst; current_cost=current_cost)
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
            travelTimeGraph.costMatrix[src, dst] = get_arc_lb_cost(
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