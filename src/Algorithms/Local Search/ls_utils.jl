# Utils function for local search neighborhoods

# TODO : adapt to multiple removals to avoid recomputaions 

# Store previous bins before removing commodities from them
function save_previous_bins(timeSpaceGraph::TimeSpaceGraph, travelTimeGraph::TravelTimeGraph, bundle::Bundle, path::Vector{Int})
    I, J, oldBins = Int[], Int[], Bin[]
    previousCost = 0.
    # For all orders
    for order in bundle.orders
        # For all arcs in the path, updating the right bins
        for (src, dst) in partition(path, 2, 1)
            timedSrc = time_space_projector(travelTimeGraph, timeSpaceGraph, src, order.deliveryDate)
            timedDst = time_space_projector(travelTimeGraph, timeSpaceGraph, dst, order.deliveryDate)
            previousCost += compute_arc_cost(timeSpaceGraph.bins[timedSrc, timedDst], timeSpaceGraph.networkArcs[timedSrc, timedDst], timeSpaceGraph.networkNodes[timedDst])
            push!(I, timedSrc)
            push!(J, timedDst)
            push!(oldBins, timeSpaceGraph.bins[timedSrc, timedDst])
        end
    end
    return sparse(I, J, oldBins), previousCost
end

# Revert the bin loading the the vector of bins given
function revert_bins!(timeSpaceGraph::TimeSpaceGraph, travelTimeGraph::TravelTimeGraph, bundle::Bundle, path::Vector{Int}, previousBins::SparseMatrixCSC{Vector{Bin}, Int})
    # For all orders
    for order in bundle.orders
        # For all arcs in the path, updating the right bins
        for (src, dst) in partition(path, 2, 1)
            timedSrc = time_space_projector(travelTimeGraph, timeSpaceGraph, src, order.deliveryDate)
            timedDst = time_space_projector(travelTimeGraph, timeSpaceGraph, dst, order.deliveryDate)
            timeSpaceGraph.bins[timedSrc, timedDst] = previousBins[timedSrc, timedDst]
        end
    end
end

# Remove order content from solution truck loads
function remove_bundle!(timeSpaceGraph::TimeSpaceGraph, travelTimeGraph::TravelTimeGraph, bundle::Bundle, path::Vector{Int})
    # For all orders
    for order in bundle.orders
        orderUniqueCom = unique(order.content)
        # For all arcs in the path, updating the right bins
        for (src, dst) in partition(path, 2, 1)
            timedSrc = time_space_projector(travelTimeGraph, timeSpaceGraph, src, order.deliveryDate)
            timedDst = time_space_projector(travelTimeGraph, timeSpaceGraph, dst, order.deliveryDate)
            for bin in timeSpaceGraph.bins[timedSrc, timedDst]
                filter!(com -> com in orderUniqueCom, bin.content)
            end
        end
    end
end

function refill_bins!(timeSpaceGraph::TimeSpaceGraph, travelTimeGraph::TravelTimeGraph, bundle::Bundle, path::Vector{Int})
    costAfterRefill = 0.
    # For all orders
    for order in bundle.orders
        # For all arcs in the path, updating the right bins
        for (src, dst) in partition(path, 2, 1)
            allCommodities = reduce(vcat, timeSpaceGraph.bins[timedSrc, timedDst])
            timedSrc = time_space_projector(travelTimeGraph, timeSpaceGraph, src, order.deliveryDate)
            timedDst = time_space_projector(travelTimeGraph, timeSpaceGraph, dst, order.deliveryDate)
            costAfterRefill += compute_arc_cost(timeSpaceGraph.bins[timedSrc, timedDst], timeSpaceGraph.networkArcs[timedSrc, timedDst], timeSpaceGraph.networkNodes[timedDst])
            empty!(timeSpaceGraph.bins[timedSrc, timedDst])
            first_fit_decreasing!(timeSpaceGraph.bins[timedSrc, timedDst], timeSpaceGraph.networkArcs[timedSrc, timedDst].capacity, allCommodities, sorted=sorted)
        end
    end
    return costAfterRefill
end

# Compute the update directly on the bins 
function update_cost_matrix!(travelTimeUtils::TravelTimeUtils, travelTimeGraph::TravelTimeGraph, updateNodes::Vector{Int}, bundle::Bundle, bundleDst::Int, bundleUtil::BundleUtils, timeSpaceUtils::TimeSpaceUtils; sorted::Bool=false)
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
                        arcOrderTrucks = first_fit_decreasing(timeSpaceGraph.bins[src, dst], arcData.capacity, order.content, sorted=sorted)
                    end
                    arcBundleCost += arcOrderTrucks * (arcData.unitCost + arcData.carbonCost)
                end
            end
            travelTimeUtils.costMatrix[src, dst] = arcBundleCost
        end
    end
end