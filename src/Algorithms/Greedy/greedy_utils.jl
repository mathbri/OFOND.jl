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
    opening_factor::Float64,
    current_cost::Bool
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
        # Arc transport cost 
        transCost = current_cost ? timeSpaceGraph.currentCost[timedSrc, timedDst] : (arcData.unitCost + arcData.carbonCost)
        arcBundleCost += get_arc_order_transport_units(timeSpaceGraph, timedSrc, timedDst, order, sorted=sorted, use_bins=use_bins) * transCost * opening_factor 
    end
    return arcBundleCost
end

# Creating start node vector
function get_all_start_nodes(
    travelTimeGraph::TravelTimeGraph, 
    bundle::Bundle
)
    src = travelTimeGraph.bundleStartNodes[bundle.idx]
    startNodes = Int[src]
    # Iterating through outneighbors of the start node
    otherSrc = findfirst(dst -> travelTimeGraph.networkArcs[src, dst].type == :shortcut, outneighbors(travelTimeGraph, src))
    # Iterating through outneighbors of the other start node 
    while otherSrc !== nothing
        push!(startNodes, otherSrc)
        src = otherSrc
        otherSrc = findfirst(dst -> travelTimeGraph.networkArcs[src, dst].type == :shortcut, outneighbors(travelTimeGraph, src))
    end
    return startNodes
end

# Updating cost matrix on the travel time graph for a specific bundle using predefined list of nodes to go through
function update_cost_matrix!(
    travelTimeGraph::TravelTimeGraph, 
    timeSpaceGraph::TimeSpaceGraph,
    bundle::Bundle; 
    sorted::Bool=false, 
    use_bins::Bool=true,
    opening_factor::Float64=1.0,
    current_cost::Bool=false
)
    # Iterating through outneighbors of the start nodes and common nodes
    for src in vcat(get_all_start_nodes(travelTimeGraph, bundle), travelTimeGraph.commonNodes)
        for dst in outneighbors(travelTimeGraph, src)
            travelTimeGraph.costMatrix[src, dst] = get_arc_update_cost(
                travelTimeGraph, timeSpaceGraph, bundle, src, dst, sorted=sorted, use_bins=use_bins, opening_factor=opening_factor, current_cost=current_cost
            )
        end
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