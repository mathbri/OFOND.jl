# Utils function only used in greedy

function sort_order_content!(instance::Instance)
    for bundle in instance.bundles
        for order in bundle.orders
            sort!(order.content, by=com->com.size, rev=true)
        end
    end
end

# TODO : check that the shotcut computation is actually true
function get_bundle_update_nodes(travelTimeUtils::TravelTimeUtils, travelTimeGraph::TravelTimeGraph, bundleIdx::Int)
    startNodes = [travelTimeUtils.bundleStartNodes[bundleIdx]]
    currentIdx = travelTimeUtils.bundleStartNodes[bundleIdx]
    while travelTimeGraph.networkArcs[currentIdx, currentIdx + 1].type == :shortcut
        push!(startNodes, currentIdx + 1)
        currentIdx += 1
    end
    # Other while condition : findfirst(node -> travelTimeGraph.networkArcs[startNode, node].type == :shortcut, outneighbors(travelTimeGraph, startNode)) !== nothing
    # Other while condition invilves way more computation
    return vcat(startNodes, travelTimeUtils.commonNodes)
end

# TODO : divide more in multiple functions, too big and too many arguments
# Updating cost matrix on the travel time graph for a specific bundle using predefined list of nodes to go through
function update_cost_matrix!(travelTimeUtils::TravelTimeUtils, travelTimeGraph::TravelTimeGraph, updateNodes::Vector{Int}, bundle::Bundle, bundleDst::Int, bundleUtil::BundleUtils, timeSpaceUtils::TimeSpaceUtils; sorted::Bool=sorted)
    # Iterating through all update nodes and their outneighbors
    for src in updateNodes
        for dst in outneighbors(travelTimeGraph, src)
            dstData = travelTimeGraph.networkNodes[dst]
            arcData = travelTimeGraph.networkArcs[src, dst]
            # If it is a shortcut leg, cost alredy set to EPS
            arcData.type == :shortcut && continue
            # If the destination is not the right plant, not updating cost
            (arcData.type == :shortcut && dst != bundleDst) && continue
            # Adding cost for each order in the bundle
            arcBundleCost = EPS
            for (idxO, order) in enumerate(bundle.orders)
                orderUtil = bundleUtil.orderUtils[idxO]
                # Node volume cost 
                arcBundleCost += dstData.volumeCost * orderUtil.volume
                # Commodity cost 
                arcBundleCost += arcData.distance * orderUtil.leadTimeCost
                # Transport cost 
                if arcData.isLinear
                    arcBundleCost += (orderUtil.volume / arcData.capacity) * arcData.unitCost
                    arcBundleCost += orderUtil.giantUnits * arcData.carbonCost
                else
                    arcOrderTrucks = orderUtil.bpUnits
                    # If the arc is not empty, computing a tentative first fit 
                    if length(timeSpaceUtils.binLoads[src, dst]) > 0
                        arcOrderTrucks = first_fit_decreasing(timeSpaceUtils.binLoads[src, dst], arcData.capacity, order.content, sorted=sorted)
                    end
                    arcBundleCost += arcOrderTrucks * (arcData.unitCost + arcData.carbonCost)
                end
            end
            travelTimeUtils.costMatrix[src, dst] = arcBundleCost
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