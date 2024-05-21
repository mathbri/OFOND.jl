# Projectors fnctions between travel time and time space

# Computing the steps to delivery to know which travel time node should be used for the order
function get_node_step_to_delivery(TSGraph::TimeSpaceGraph, TSNode::Int, delDate::Int)
    stepToDel = delDate - TSGraph.timeSteps[TSNode]
    # If the step to delivery is negative, adding the time horizon to it
    stepToDel < 0 && (stepToDel += TSGraph.timeHorizon)
    return stepToDel
end

# Project a node of the time space graph on the travel time graph for a specific delivery date
# return -1 if the step to delivery is greater than the maximum delivery time 
function travel_time_projector(
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    timeSpaceNode::Int,
    deliveryDate::Int,
    maxDeliveryTime::Int,
)
    # Compute the step to delivery and corresponding node hash 
    stepToDel = get_node_step_to_delivery(timeSpaceGraph, timeSpaceNode, deliveryDate)
    # If greater than max delivery time, returning -1
    stepToDel > maxDeliveryTime && return -1
    ttNodeHash = hash(stepToDel, timeSpaceGraph.networkNodes[timeSpaceNode].hash)
    # Using time space link dict to return the right node idx or -1
    return get(travelTimeGraph.hashToIdx, ttNodeHash, -1)
end

# Wrapper for Order and Bundle objects
function travel_time_projector(
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    TSNode::Int,
    order::Order,
    bundle::Bundle,
)
    # Fail safe if the order and bundle are unrelated
    order.bundleHash != bundle.hash && return -1
    return travel_time_projector(
        TTGraph, TSGraph, TSNode, order.deliveryDate, bundle.maxDelTime
    )
end

# Project an arc of the travel time graph on the time space graph for a specific delivery date
function travel_time_projector(
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    TSSrc::Int,
    TSDst::Int,
    order::Order,
    bundle::Bundle,
)
    return (
        travel_time_projector(TTGraph, TSGraph, TSSrc, order, bundle),
        travel_time_projector(TTGraph, TSGraph, TSDst, order, bundle),
    )
end

# Project a node of the travel time graph on the time space graph for a specific delivery date 
function time_space_projector(
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    travelTimeNode::Int,
    deliveryDate::Int,
)
    # Computing the time step from the delivery date and the steps from delivery
    timeSpaceDate = deliveryDate - travelTimeGraph.stepToDel[travelTimeNode]
    # If it goes out of the horizon, rolling it back to the top
    timeSpaceDate < 1 && (timeSpaceDate += timeSpaceGraph.timeHorizon)
    # Using travel time link dict to return the right node idx
    nodeData = travelTimeGraph.networkNodes[travelTimeNode]
    return timeSpaceGraph.hashToIdx[hash(timeSpaceDate, nodeData.hash)]
end

# Wrapper for Order object
function time_space_projector(
    TTGraph::TravelTimeGraph, TSGraph::TimeSpaceGraph, TTNode::Int, order::Order
)
    return time_space_projector(TTGraph, TSGraph, TTNode, order.deliveryDate)
end

# Project an arc of the travel time graph on the time space graph for a specific order
function time_space_projector(
    TTGraph::TravelTimeGraph, TSGraph::TimeSpaceGraph, TTSrc::Int, TTDst::Int, order::Order
)
    return (
        time_space_projector(TTGraph, TSGraph, TTSrc, order.deliveryDate),
        time_space_projector(TTGraph, TSGraph, TTDst, order.deliveryDate),
    )
end

# Project a path of the travel time graph on the time space graph for a specific order
function time_space_projector(
    TTGraph::TravelTimeGraph, TSGraph::TimeSpaceGraph, TTPath::Vector{Int}, order::Order
)
    # Refs are used here to broadcat operation only on the path
    return time_space_projector.(
        Ref(TTGraph), Ref(TSGraph), TTPath, Ref(order.deliveryDate)
    )
end