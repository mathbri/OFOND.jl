# Updating functions for the bins

# TODO : harmonize arc cost computation
function compute_new_cost(
    arcData::NetworkArc, dstData::NetworkNode, newBins::Int, commodities::Vector{Commodity}
)
    volume = sum(com.size for com in commodities)
    leadTimeCost = sum(com.stockCost for com in commodities)
    # Node cost 
    cost =
        dstData.volumeCost * volume / VOLUME_FACTOR +
        arcData.carbonCost * volume / arcData.capacity
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

# TODO : a lot of garbage collecting for the projection
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
        timedPath = time_space_projector(TTGraph, TSGraph, path, order)
        if -1 in timedPath
            bundleSrcDst = (TTGraph.bundleSrc[bundle.idx], TTGraph.bundleDst[bundle.idx])
            pathStr = join(path, ", ")
            pathInfo = join(string.(TTGraph.networkNodes[path]), ", ")
            pathSteps = join(string.(TTGraph.stepToDel[path]), ", ")
            timedPathStr = join(timedPath, ", ")
            @error "At least one node was not projected in bin updating" :bundle = bundle :bundleSrcDst =
                bundleSrcDst :order = order :path = pathStr :pathInfo = pathInfo :pathSteps =
                pathSteps :timedPath = timedPathStr
        end
        # Add or Remove order
        if remove
            costAdded += remove_order!(solution, TSGraph, timedPath, order)
        else
            costAdded += add_order!(solution, TSGraph, timedPath, order; sorted=sorted)
        end
    end
    return costAdded
end