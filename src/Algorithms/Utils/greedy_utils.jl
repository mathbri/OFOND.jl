# Utils function only used in greedy

# TODO : when solution struct updated, replace paths with solution and get path with the bundle idx

# Check whether the arc is fit for a cost update
function is_update_candidate(arcData::NetworkArc, dst::Int, bundleDst::Int)
    # If it is a shortcut leg, cost alredy set to EPS
    arcData.type == :shortcut && return false
    # If the destination is not the right plant, not updating cost
    (arcData.type == :delivery && dst != bundleDst) && return false
    return true
end

function get_order_node_com_cost(TTGraph::TravelTimeGraph, src::Int, dst::Int, order::Order)
    arcData = TTGraph.networkArcs[src, dst]
    dstData = TTGraph.networkNodes[dst]
    # Node volume cost + Commodity last time cost  
    return dstData.volumeCost * order.volume + arcData.distance * order.leadTimeCost
end

function get_order_transport_units(
    solution::Solution,
    TSGraph::TimeSpaceGraph,
    timedSrc::Int,
    timedDst::Int,
    order::Order;
    sorted::Bool,
    use_bins::Bool,
)
    arcData = TSGraph.networkArcs[timedSrc, timedDst]
    # Transport cost 
    arcOrderTrucks = get_transport_units(order, arcData)
    # If we take into account the current solution
    if use_bins
        loads = solution.binLoads[timedSrc, timedDst]
        # If the arc is not empty, computing a tentative first fit 
        if length(loads) > 0
            arcOrderTrucks = first_fit_decreasing(
                loads, arcData.capacity, order.content; sorted=sorted
            )
        end
    end
    return arcOrderTrucks
end

function get_transport_cost(
    TSGraph::TimeSpaceGraph, timedSrc::Int, timedDst::Int; current_cost::Bool
)
    current_cost && return TSGraph.currentCost[timedSrc, timedDst]
    arcData = TSGraph.networkArcs[timedSrc, timedDst]
    return (arcData.unitCost + arcData.carbonCost)
end

function get_arc_update_cost(
    solution::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
    sorted::Bool,
    use_bins::Bool,
    opening_factor::Float64,
    current_cost::Bool,
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
                solution,
                TSGraph,
                timedSrc,
                timedDst,
                order;
                sorted=sorted,
                use_bins=use_bins,
            ) *
            get_transport_cost(TSGraph, timedSrc, timedDst; current_cost=current_cost) *
            opening_factor
    end
    return arcBundleCost
end

function find_other_src_node(travelTimeGraph::TravelTimeGraph, src::Int)
    return findfirst(
        dst -> travelTimeGraph.networkArcs[src, dst].type == :shortcut,
        outneighbors(travelTimeGraph, src),
    )
end

# Creating start node vector
function get_all_start_nodes(travelTimeGraph::TravelTimeGraph, bundle::Bundle)
    src = travelTimeGraph.bundleSrc[bundle.idx]
    startNodes = Int[src]
    # Iterating through outneighbors of the start node
    otherSrc = find_other_src_node(travelTimeGraph, src)
    # Iterating through outneighbors of the other start node 
    while otherSrc !== nothing
        push!(startNodes, otherSrc)
        src = otherSrc
        otherSrc = find_other_src_node(travelTimeGraph, src)
    end
    return startNodes
end

# TODO : moving order loop to the most outer one allow to directly project src node before looping over dst node
# Once the src node is projected, doesn't need to project dst, just looping over outneighbors of projected node
# How do i get the dst in the TTGraph for the cost update ?
# How do I handle the fact that the final arc cost will be known at the end of the order loop ?

# Updating cost matrix on the travel time graph for a specific bundle 
function update_cost_matrix!(
    solution::Solution,
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    bundle::Bundle;
    sorted::Bool=false,
    use_bins::Bool=true,
    opening_factor::Float64=1.0,
    current_cost::Bool=false,
)
    # Iterating through outneighbors of the start nodes and common nodes
    for src in
        vcat(get_all_start_nodes(travelTimeGraph, bundle), travelTimeGraph.commonNodes)
        for dst in outneighbors(travelTimeGraph, src)
            travelTimeGraph.costMatrix[src, dst] = get_arc_update_cost(
                solution,
                travelTimeGraph,
                timeSpaceGraph,
                bundle,
                src,
                dst;
                sorted=sorted,
                use_bins=use_bins,
                opening_factor=opening_factor,
                current_cost=current_cost,
            )
        end
    end
end

# Check whether the path of the bundle needs to be recomputed
function is_path_admissible(travelTimeGraph::TravelTimeGraph, path::Vector{Int})
    # Checking elementarity on network
    return is_path_elementary(travelTimeGraph, path)
    # Too long ? Too many node ? To be difined
end

function get_path_cost(path::Vector{Int}, costMatrix::SparseMatrixCSC{Float64,Int})
    cost = 0.0
    for (i, j) in partition(path, 2, 1)
        cost += costMatrix[i, j]
    end
    return cost
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
    return deleteat!(path, 1:(firstNode - 1))
end

function remove_shotcuts!(path::Vector{Edge}, travelTimeGraph::TravelTimeGraph)
    firstEdge = findfirst(
        edge -> travelTimeGraph.networkArcs[edge.src, edge.dst].type != :shortcut, path
    )
    return deleteat!(path, 1:(firstEdge - 1))
end