# Projectors fnctions between travel time and time space

function get_node_step_to_delivery(
    timeSpaceGraph::TimeSpaceGraph, timeSpaceNode::Int, order::Order
)
    # Computing the steps to delivery to know which travel time node should be used for the order
    stepToDel = order.deliveryDate - timeSpaceGraph.timeSteps[timeSpaceNode]
    # If the step to delivery is negative, adding the time horizon to it
    stepToDel < 0 && (stepToDel += timeSpaceGraph.timeHorizon)
    return stepToDel
end

# Project a node of the time space graph on the travel time graph for a specific order
# return -1 if the node time step is after the order delivery date or if the step to delivery is greater than the maximum delivery time 
function travel_time_projector(
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    timeSpaceNode::Int,
    order::Order,
)
    # If the time step is after the order delivery date, return -1
    timeSpaceGraph.timeSteps[timeSpaceNode] > order.deliveryDate && return -1
    # If the step to delivery is greater than the max delivery time, return -1
    stepToDel = get_node_step_to_delivery(timeSpaceGraph, timeSpaceNode, order)
    stepToDel > order.bundle.maxDeliveryTime && return -1
    # Using time space link dict to return the right node idx
    return travelTimeGraph.hashToIdx[hash(
        stepToDel, timeSpaceGraph.networkNodes[timeSpaceNode].hash
    )]
end

function travel_time_projector(
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    timeSpaceSource::Int,
    timeSpaceDest::Int,
    order::Order,
)
    return (
        travel_time_projector(travelTimeGraph, timeSpaceGraph, timeSpaceSource, order),
        travel_time_projector(travelTimeGraph, timeSpaceGraph, timeSpaceDest, order),
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

# Project an arc of the travel time graph on the time space graph for a specific delivery date 
function time_space_projector(
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    travelTimeSource::Int,
    travelTimeDest::Int,
    deliveryDate::Int,
)
    return (
        time_space_projector(
            travelTimeGraph, timeSpaceGraph, travelTimeSource, deliveryDate
        ),
        time_space_projector(travelTimeGraph, timeSpaceGraph, travelTimeDest, deliveryDate),
    )
end

# Project a path of the travel time graph on the time space graph for a specific delivery date 
function time_space_projector(
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    travelTimePath::Vector{Int},
    deliveryDate::Int,
)
    # Refs are used here to broadcat operation only on the path
    return time_space_projector.(
        Ref(travelTimeGraph), Ref(timeSpaceGraph), travelTimePath, Ref(deliveryDate)
    )
end