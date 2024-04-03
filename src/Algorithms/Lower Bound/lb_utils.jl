# Functions used for lower bound computation

function get_arc_order_transport_units(
    timeSpaceGraph::TimeSpaceGraph, 
    timedSrc::Int, 
    timedDst::Int, 
    order::Order;
)
    arcData = timeSpaceGraph.networkArcs[timedSrc, timedDst]
    # Transport cost 
    return get_lb_transport_units(order, arcData)
end

function get_arc_update_cost(
    travelTimeGraph::TravelTimeGraph, 
    timeSpaceGraph::TimeSpaceGraph, 
    bundle::Bundle, 
    src::Int, 
    dst::Int; 
)
    bundleDst = travelTimeGraph.bundleEndNodes[bundle.idx]
    dstData, arcData = travelTimeGraph.networkNodes[dst], travelTimeGraph.networkArcs[src, dst]
    # If the arc doesn't need an update, skipping
    is_update_candidate(arcData, dst, bundleDst) || return travelTimeGraph.costMatrix[src, dst]
    # Otherwise, computing the new cost
    arcBundleCost = EPS
    for order in bundle.orders
        # Getting time space projection
        timedSrc, timedDst = time_space_projector(travelTimeGraph, timeSpaceGraph, src, dst, order.deliveryDate)
        # Node volume cost 
        arcBundleCost = dstData.volumeCost * order.volume
        # Commodity cost 
        arcBundleCost += arcData.distance * order.leadTimeCost
        # Arc order cost 
        arcBundleCost += get_arc_order_transport_units(timeSpaceGraph, timedSrc, timedDst, order) * (arcData.unitCost + arcData.carbonCost)
    end
    return arcBundleCost
end

# Updating cost matrix on the travel time graph for a specific bundle using predefined list of nodes to go through
function update_cost_matrix!(
    travelTimeGraph::TravelTimeGraph, 
    timeSpaceGraph::TimeSpaceGraph,
    bundle::Bundle
)
    # Iterating through outneighbors of the start node
    src = travelTimeGraph.bundleStartNodes[bundle.idx]
    for dst in outneighbors(travelTimeGraph, src)
        # Adding cost for each order in the bundle
        travelTimeUtils.costMatrix[src, dst] = get_arc_update_cost(travelTimeGraph, timeSpaceGraph, bundle, src, dst)
    end
    # Iterating through outneighbors of the common nodes
    for src in travelTimeGraph.commonNodes
        for dst in outneighbors(travelTimeGraph, src)
            travelTimeUtils.costMatrix[src, dst] = get_arc_update_cost(travelTimeGraph, timeSpaceGraph, bundle, src, dst)
        end
    end
    # Iterating through outneighbors of the other start node (using while condition on the existence of an outneighbor linked with a shortcut arc)
    otherSrc = findfirst(node -> travelTimeGraph.networkArcs[startNode, node].type == :shortcut, outneighbors(travelTimeGraph, src))
    while otherSrc !== nothing
        src = otherSrc
        for dst in outneighbors(travelTimeGraph, src)
            travelTimeUtils.costMatrix[src, dst] = get_arc_update_cost(travelTimeGraph, timeSpaceGraph, bundle, src, dst)
        end
        otherSrc = findfirst(node -> travelTimeGraph.networkArcs[startNode, node].type == :shortcut, outneighbors(travelTimeGraph, src))
    end
end