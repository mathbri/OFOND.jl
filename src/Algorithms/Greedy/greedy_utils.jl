# Utils function only used in greedy

function sort_order_content!(instance::Instance)
    for bundle in instance.bundles
        for order in bundle.orders
            sort!(order.content, by=com->com.size, rev=true)
        end
    end
end

# Check whether the arc is fit for a cost update
function is_update_candidate(arcData::NetworkArc, dst::Int, bundleDst::Int)
    # If it is a shortcut leg, cost alredy set to EPS
    arcData.type == :shortcut && return false
    # If the destination is not the right plant, not updating cost
    (arcData.type == :delivery && dst != bundleDst) && return false
    return true
end

function get_arc_order_transport_units(
    timeSpaceGraph::TimeSpaceGraph, 
    timedSrc::Int, 
    timedDst::Int, 
    order::Order;
    sorted::Bool, 
    use_bins::Bool
)
    arcData = timeSpaceGraph.networkArcs[timedSrc, timedDst]
    # Transport cost 
    arcOrderTrucks = get_transport_units(order, arcData)
    # If we take into account the current solution
    if use_bins
        # If the arc is not empty, computing a tentative first fit 
        if length(timeSpaceGraph.binLoads[timedSrc, timedDst]) > 0
            arcOrderTrucks = first_fit_decreasing(binOrLoad, arcData.capacity, order.content, sorted=sorted)
        end
    end
    return arcOrderTrucks
end

function get_arc_update_cost(
    travelTimeGraph::TravelTimeGraph, 
    timeSpaceGraph::TimeSpaceGraph, 
    bundle::Bundle, 
    src::Int, 
    dst::Int; 
    sorted::Bool,
    use_bins::Bool,
    opening_factor::Float64
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
        arcBundleCost += dstData.volumeCost * order.volume
        # Commodity cost 
        arcBundleCost += arcData.distance * order.leadTimeCost
        # Arc order cost 
        arcBundleCost += get_arc_order_transport_units(timeSpaceGraph, timedSrc, timedDst, order, sorted=sorted, use_bins=use_bins) * (arcData.unitCost + arcData.carbonCost) * opening_factor 
    end
    return arcBundleCost
end

# Same function specialized for current cost computation 
# TODO : find a way to factorize or be very careful when changing one or the other
function get_arc_update_cost(
    travelTimeGraph::TravelTimeGraph, 
    timeSpaceGraph::TimeSpaceGraph, 
    bundle::Bundle, 
    src::Int, 
    dst::Int,
    currentCost::SparseMatrixCSC{Float64, Int};
    sorted::Bool,
    use_bins::Bool,
    opening_factor::Float64
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
        arcBundleCost += dstData.volumeCost * order.volume
        # Commodity cost 
        arcBundleCost += arcData.distance * order.leadTimeCost
        # Arc order cost 
        arcBundleCost += get_arc_order_transport_units(timeSpaceGraph, timedSrc, timedDst, order, sorted=sorted, use_bins=use_bins) * currentCost[timedSrc, timedDst] * opening_factor
    end
    return arcBundleCost
end

# Updating cost matrix on the travel time graph for a specific bundle using predefined list of nodes to go through
function update_cost_matrix!(
    travelTimeGraph::TravelTimeGraph, 
    timeSpaceGraph::TimeSpaceGraph,
    bundle::Bundle; 
    sorted::Bool=false, 
    use_bins::Bool=true,
    opening_factor::Float64=1.0
)
    # Iterating through outneighbors of the start node
    src = travelTimeGraph.bundleStartNodes[bundle.idx]
    for dst in outneighbors(travelTimeGraph, src)
        # Adding cost for each order in the bundle
        travelTimeUtils.costMatrix[src, dst] = get_arc_update_cost(travelTimeGraph, timeSpaceGraph, bundle, src, dst, sorted=sorted, use_bins=use_bins, opening_factor=opening_factor)
    end
    # Iterating through outneighbors of the common nodes
    for src in travelTimeGraph.commonNodes
        for dst in outneighbors(travelTimeGraph, src)
            travelTimeUtils.costMatrix[src, dst] = get_arc_update_cost(travelTimeGraph, timeSpaceGraph, bundle, src, dst, sorted=sorted, use_bins=use_bins, opening_factor=opening_factor)
        end
    end
    # Iterating through outneighbors of the other start node (using while condition on the existence of an outneighbor linked with a shortcut arc)
    otherSrc = findfirst(node -> travelTimeGraph.networkArcs[startNode, node].type == :shortcut, outneighbors(travelTimeGraph, src))
    while otherSrc !== nothing
        src = otherSrc
        for dst in outneighbors(travelTimeGraph, src)
            travelTimeUtils.costMatrix[src, dst] = get_arc_update_cost(travelTimeGraph, timeSpaceGraph, bundle, src, dst, sorted=sorted, use_bins=use_bins, opening_factor=opening_factor)
        end
        otherSrc = findfirst(node -> travelTimeGraph.networkArcs[startNode, node].type == :shortcut, outneighbors(travelTimeGraph, src))
    end
end

# Specialized version of the previous for the current cost
function update_cost_matrix!(
    travelTimeGraph::TravelTimeGraph, 
    timeSpaceGraph::TimeSpaceGraph,
    bundle::Bundle,
    currentCost::SparseMatrixCSC{Float64, Int}; 
    sorted::Bool=false, 
    use_bins::Bool=true,
    opening_factor::Float64=1.0
)
    # Iterating through outneighbors of the start node
    src = travelTimeGraph.bundleStartNodes[bundle.idx]
    for dst in outneighbors(travelTimeGraph, src)
        # Adding cost for each order in the bundle
        travelTimeUtils.costMatrix[src, dst] = get_arc_update_cost(travelTimeGraph, timeSpaceGraph, bundle, src, dst, currentCost, sorted=sorted, use_bins=use_bins, opening_factor=opening_factor)
    end
    # Iterating through outneighbors of the common nodes
    for src in travelTimeGraph.commonNodes
        for dst in outneighbors(travelTimeGraph, src)
            travelTimeUtils.costMatrix[src, dst] = get_arc_update_cost(travelTimeGraph, timeSpaceGraph, bundle, src, dst, currentCost, sorted=sorted, use_bins=use_bins, opening_factor=opening_factor)
        end
    end
    # Iterating through outneighbors of the other start node (using while condition on the existence of an outneighbor linked with a shortcut arc)
    otherSrc = findfirst(node -> travelTimeGraph.networkArcs[startNode, node].type == :shortcut, outneighbors(travelTimeGraph, src))
    while otherSrc !== nothing
        src = otherSrc
        for dst in outneighbors(travelTimeGraph, src)
            travelTimeUtils.costMatrix[src, dst] = get_arc_update_cost(travelTimeGraph, timeSpaceGraph, bundle, src, dst, currentCost, sorted=sorted, use_bins=use_bins, opening_factor=opening_factor)
        end
        otherSrc = findfirst(node -> travelTimeGraph.networkArcs[startNode, node].type == :shortcut, outneighbors(travelTimeGraph, src))
    end
end

function remove_shortcuts!(path::Vector{Int}, travelTimeGraph::TravelTimeGraph)
    firstNode = 1
    for (src, dst) in partition(path, 2, 1)
        if travelTimeGraph.networkArcs[src, dst].type == :shortcut
            firstNode += 1
        else
            break
        end
    end
    deleteat!(path, 1:(firstNode-1))
end

function remove_shotcuts!(path::Vector{Edge}, travelTimeGraph::TravelTimeGraph)
    firstEdge = findfirst(edge -> travelTimeGraph.networkArcs[edge.src, edge.dst].type != :shortcut, path)
    deleteat!(path, 1:(firstEdge-1))
end