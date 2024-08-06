# Utils function only used in greedy

# TODO : carbon cost for direct arcs are not linear

# Check whether the arc is fit for a cost update
function is_update_candidate(TTGraph::TravelTimeGraph, src::Int, dst::Int, bundle::Bundle)
    arcData = TTGraph.networkArcs[src, dst]
    # If it is a shortcut leg, cost alredy set to EPS
    arcData.type == :shortcut && return false
    bundleDst = TTGraph.bundleDst[bundle.idx]
    # If the destination is not the right plant, not updating cost
    (arcData.type == :delivery && dst != bundleDst) && return false
    return true
end

# Check whether the arc is forbidden for the bundle
function is_forbidden(TTGraph::TravelTimeGraph, src::Int, dst::Int, bundle::Bundle)
    # If it is an inland bundle, I want to avoid ports
    inlandBundle = (bundle.customer.continent == bundle.supplier.continent)
    return (inlandBundle && (is_port(TTGraph, src) || is_port(TTGraph, dst)))
end

# Computes volume and lead time costs for an order
function volume_stock_cost(TTGraph::TravelTimeGraph, src::Int, dst::Int, order::Order)
    dstData, arcData = TTGraph.networkNodes[dst], TTGraph.networkArcs[src, dst]
    # Node volume cost + Arc carbon cost + Commodity last time cost
    return (dstData.volumeCost + arcData.carbonCost) * order.volume /
           (VOLUME_FACTOR * arcData.capacity) + arcData.distance * order.leadTimeCost
end

# Computes transport units for an order
function transport_units(
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
    orderTrucks = get_transport_units(order, arcData)
    # If we take into account the current solution
    if use_bins && !arcData.isLinear
        bins = solution.bins[timedSrc, timedDst]
        # If the arc is not empty, computing a tentative first fit 
        if length(bins) > 0
            orderTrucks = tentative_first_fit(bins, arcData, order; sorted=sorted)
        end
    end
    return orderTrucks
end

# Returns the corresponding transport costs to be used
function transport_cost(
    TSGraph::TimeSpaceGraph, timedSrc::Int, timedDst::Int; current_cost::Bool
)
    current_cost && return TSGraph.currentCost[timedSrc, timedDst]
    return TSGraph.networkArcs[timedSrc, timedDst].unitCost
end

# Compute the arc update cost to be used in the path computation
function arc_update_cost(
    sol::Solution,
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
    sorted::Bool=false,
    use_bins::Bool=true,
    opening_factor::Float64=1.0,
    current_cost::Bool=false,
)
    # If the arc is forbidden for the bundle, returning INF
    is_forbidden(TTGraph, src, dst, bundle) && return INFINITY
    # Otherwise, computing the new cost
    arcBundleCost = EPS
    for order in bundle.orders
        # Getting time space projection
        tSrc, tDst = time_space_projector(TTGraph, TSGraph, src, dst, order)
        # Node volume cost 
        arcBundleCost += volume_stock_cost(TTGraph, src, dst, order)
        # Arc transport cost 
        arcBundleCost +=
            transport_units(
                sol, TSGraph, tSrc, tDst, order; sorted=sorted, use_bins=use_bins
            ) *
            transport_cost(TSGraph, tSrc, tDst; current_cost=current_cost) *
            opening_factor
    end
    return arcBundleCost
end

function find_other_src_node(travelTimeGraph::TravelTimeGraph, src::Int)
    otherSrcIdx = findfirst(
        dst -> travelTimeGraph.networkArcs[src, dst].type == :shortcut,
        outneighbors(travelTimeGraph.graph, src),
    )
    otherSrcIdx === nothing && return nothing
    return outneighbors(travelTimeGraph.graph, src)[otherSrcIdx]
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
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundle::Bundle;
    sorted::Bool=false,
    use_bins::Bool=true,
    opening_factor::Float64=1.0,
    current_cost::Bool=false,
)
    # Iterating through outneighbors of the start nodes and common nodes
    for src in vcat(get_all_start_nodes(TTGraph, bundle), TTGraph.commonNodes)
        for dst in outneighbors(TTGraph.graph, src)
            # If the arc doesn't need an update, skipping
            is_update_candidate(TTGraph, src, dst, bundle) || continue
            # Otherwise, computing the new cost
            TTGraph.costMatrix[src, dst] = arc_update_cost(
                solution,
                TTGraph,
                TSGraph,
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

function path_cost(path::Vector{Int}, costMatrix::SparseMatrixCSC{Float64,Int})
    cost = 0.0
    for (i, j) in partition(path, 2, 1)
        cost += costMatrix[i, j]
    end
    return cost
end
