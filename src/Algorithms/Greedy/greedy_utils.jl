# Utils function only used in greedy

function sort_order_content!(instance::Instance)
    for bundle in instance.bundles
        for order in bundle.orders
            sort!(order.content, by=com->com.size, rev=true)
        end
    end
end

# TODO : adapt to the new arguments 
function update_cost_matrix!(travelTimeUtils::TravelTimeUtils, travelTimeGraph::TravelTimeGraph, bundle::Bundle, timeSpaceUtils::TimeSpaceUtils)
    calT = get_prop(network, :calT)
    for edge in edges(network)
        srcHash, dstHash = get_prop(network, src(edge), :hash), get_prop(network, dst(edge), :hash)
        # If it is a shortcut leg, weight alredy set to EPS
        if srcHash == dstHash
            continue
        end
        # By default, free arc
        edgeBundleCost = EPS
        edgeInfo = instance.legs[hash(srcHash, hash(dstHash))]
        # Some legs are forbidden but only for some bundles so multiplying cost by 10
        outsourceOtherNode = (edgeInfo.type == OUTSOURCE) && (srcHash != bundle.supplier)
        deliveryOtherPlant = (edgeInfo.type == DELIVERY) && (dstHash != bundle.customer)
        if outsourceOtherNode || deliveryOtherPlant
            bundleTrucks = sum(instance.orders[orderHash].ffdTrucks for orderHash in bundle.orders)
            edgeBundleCost *= bundleTrucks * 10 * edgeInfo.truckCost 
            edgeBundleCost += 1_000_000
            set_prop!(network, edge, :weight, edgeBundleCost)
            continue
        end
        # Adding cost for each order in the bundle
        for orderHash in bundle.orders
            order = instance.orders[orderHash]
            # Computing order trucks if there is a point
            edgeOrderTrucks = order.ffdTrucks
            # If it is a massified edge, applying cost obtained via ffd loading
            if edgeInfo.truckCost > EPS
                stepsToDelivery = Int8(calT - get_prop(network, src(edge), :timeStep))
                timeToFill = get_timeIdx_to_fill(instance, order, stepsToDelivery)
                truckLoadHash = hash(edgeInfo, timeToFill)
                if haskey(truckLoads, truckLoadHash)
                    edgeOrderTrucks = compute_trucks_added(order, truckLoads[truckLoadHash], instance.commodities)
                end            
            end
            # By default, free arc and then we add possible volume and truck costs
            edgeOrderVolumeCost = edgeInfo.volumeCost * order.volume / 100
            @assert edgeOrderVolumeCost >= 0 "Edge cost cannot be negative"
            edgeOrderTruckCost = edgeInfo.truckCost * edgeOrderTrucks
            @assert edgeOrderTruckCost >= 0 "Edge cost cannot be negative"
            edgeOrderCost = EPS + edgeOrderVolumeCost + edgeOrderTruckCost
            @assert edgeOrderCost > 0 "Edge cost cannot be negative"
            edgeBundleCost += edgeOrderCost
        end
        set_prop!(network, edge, :weight, edgeBundleCost)
    end
end