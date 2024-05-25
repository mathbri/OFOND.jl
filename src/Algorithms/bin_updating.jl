# Updating functions for the bins

# TODO : add current_cost option for this all all other functions
function compute_new_cost(
    arcData::NetworkArc, dstData::NetworkNode, newBins::Int, commodities::Vector{Commodity}
)
    volume = sum(size(com) for com in commodities) / VOLUME_FACTOR
    leadTimeCost = sum(lead_time_cost(com) for com in commodities)
    # Node cost 
    cost = (dstData.volumeCost + arcData.carbonCost) * volume
    # Transport cost 
    addedBins = arcData.isLinear ? (volume / arcData.capacity) : newBins
    cost += addedBins * arcData.unitCost
    # Commodity cost
    return cost += arcData.distance * leadTimeCost
end

# Add order content to solution truck loads with packing function
function add_order!(
    solution::Solution,
    TSGraph::TimeSpaceGraph,
    timedPath::Vector{Int},
    order::Order;
    sorted::Bool=false,
)
    costAdded = 0.0
    for (timedSrc, timedDst) in partition(timedPath, 2, 1)
        bins = solution.bins[timedSrc, timedDst]
        dstData = TSGraph.networkNodes[timedDst]
        arcData = TSGraph.networkArcs[timedSrc, timedDst]
        # Updating bins
        addedBins = first_fit_decreasing!(bins, arcData, order; sorted=sorted)
        # Updating cost
        costAdded += compute_new_cost(arcData, dstData, addedBins, order.content)
    end
    return costAdded
end

# Remove order content from solution truck loads, does not refill bins
function remove_order!(
    solution::Solution, TSGraph::TimeSpaceGraph, timedPath::Vector{Int}, order::Order;
)
    costAdded, orderUniqueCom = 0.0, unique(order.content)
    # For all arcs in the path, updating the right bins
    for (timedSrc, timedDst) in partition(timedPath, 2, 1)
        for bin in solution.bins[timedSrc, timedDst]
            remove!(bin, orderUniqueCom)
        end
        dstData = TSGraph.networkNodes[timedDst]
        arcData = TSGraph.networkArcs[timedSrc, timedDst]
        costAdded -= compute_new_cost(arcData, dstData, 0, order.content)
    end
    return costAdded
end

function update_bins!(
    solution::Solution,
    TSGraph::TimeSpaceGraph,
    TTGraph::TravelTimeGraph,
    bundle::Bundle,
    path::Vector{Int};
    sorted::Bool=false,
    remove::Bool=false,
)
    costAdded = 0.0
    for order in bundle.orders
        # Projecting path
        timedPath = time_space_projector(TTGraph, TSGraph, path, order.deliveryDate)
        # Add or Remove order
        if remove
            costAdded += remove_order!(solution, TSGraph, timedPath, order)
        else
            costAdded += add_order!(solution, TSGraph, timedPath, order; sorted=sorted)
        end
    end
    return costAdded
end