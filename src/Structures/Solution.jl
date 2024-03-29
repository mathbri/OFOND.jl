# Solution structure

struct Solution
    # Travel time graph (on which paths are computed)
    travelTimeGraph :: TravelTimeGraph
    # Paths used for delivery
    bundlePaths :: Vector{Vector{Int}}
    # Transport units completion through time 
    travelTimeGraph :: travelTimeGraph
end

# Methods

# Plot some of the paths on a map ?
# Compute some import statistics ? (the ones in solution indicators for ex)
function analyze_solution()
    
end

# Check whether a solution is feasible or not 
function is_feasible(instance::Instance, solution::Solution; verbose::Bool=false)
    # There is enough paths : one for every bundle
    if length(instance.bundles) != length(solution.bundlePaths)
        verbose && @warn "Infeasible solution : $(length(instance.bundles)) bundles and $(length(solution.bundlePaths)) paths"
        return false
    end
    # All commodities are delivered : start from supplier with right quantities, and arrives at customer, with right quantities
    for (idxB, bundle) in enumerate(instance.bundles)
        bundlePath = solution.bundlePaths[idxB]
        pathSupplier = solution.travelTimeGraph.networkNodes[bundlePath[1]]
        pathCustomer = solution.travelTimeGraph.networkNodes[bundlePath[end]]
        # Checking supplier
        if bundle.supplier != pathSupplier
            verbose && @warn "Infeasible solution : bundle $idxB has supplier $(bundle.supplier) and its path starts at $(pathSupplier)"
            return false
        end
        # Checking customer
        if bundle.customer != pathCustomer
            verbose && @warn "Infeasible solution : bundle $idxB has customer $(bundle.customer) and its path ends at $(pathCustomer)"
            return false
        end
        # Checking that the right quantities are associated
        for order in bundle.orders 
            # Getting the timed first arc
            timedSourceIdx = time_space_projector(solution.travelTimeGraph, solution.timeSpaceGraph, bundlePath[1], order.deliveryDate)
            timedDestIdx = time_space_projector(solution.travelTimeGraph, solution.timeSpaceGraph, bundlePath[2], order.deliveryDate)
            # Checking quantities in this arc
            allArcCommodities = reduce(vcat, solution.timeSpaceGraph.bins[timedSourceIdx, timedDestIdx])
            orderUniqueCom = unique(order.content)
            routedCommodities = sort(filter(com -> com in orderUniqueCom, allArcCommodities))
            if sort(order.content) != routedCommodities
                verbose && @warn "Infeasible solution : order $order (bundle $idxB) misses quantities on the first arc ($timedSourceIdx-$timedDestIdx)" :inOrder=order.content :onArc=routedCommodities
                return false    
            end
            # Getting the timed last arc
            timedSourceIdx = time_space_projector(solution.travelTimeGraph, solution.timeSpaceGraph, bundlePath[end-1], order.deliveryDate)
            timedDestIdx = time_space_projector(solution.travelTimeGraph, solution.timeSpaceGraph, bundlePath[end], order.deliveryDate)
            # Checking quantities in this arc
            allArcCommodities = reduce(vcat, solution.timeSpaceGraph.bins[timedSourceIdx, timedDestIdx])
            orderUniqueCom = unique(order.content)
            routedCommodities = sort(filter(com -> com in orderUniqueCom, allArcCommodities))
            if sort(order.content) != routedCommodities
                verbose && @warn "Infeasible solution : order $order (bundle $idxB) misses quantities on the last arc ($timedSourceIdx-$timedDestIdx)" :inOrder=order.content :onArc=routedCommodities
                return false    
            end
        end
    end
end

# Detect all infeasibility in a solution

# Compute the cost of a solution : node cost + arc cost + commodity cost
function compute_cost(solution::Solution)
    totalCost = 0.
    for arc in edges(solution.travelTimeGraph)
        arcBins = solution.travelTimeGraph.bins[src(arc), dst(arc)]
        # If there is no bins, skipping arc
        length(arcBins) == 0 && continue
        # Accesing and computing useful informations
        destNode = solution.travelTimeGraph.networkNodes[dst(arc)]
        arcData = solution.travelTimeGraph.networkArcs[src(arc), dst(arc)]
        arcVolume = sum(arcData.capacity - bin.availableCapacity for bin in arcBins) / VOLUME_FACTOR
        arcLeadTimeCost = sum(sum(commodity.leadTimeCost for commodity in bin) for bin in arcBins)
        # Node cost 
        totalCost += destNode.volumeCost * arcVolume
        # Transport cost 
        if arcData.isLinear
            totalCost += (arcVolume / arcData.capacity) * arcData.unitCost
        else
            totalCost += length(arcBins) * arcData.unitCost
        end
        # Carbon cost 
        totalCost += length(arcBins) * arcData.carbonCost
        # Commodity cost
        totalCost += arcData.distance * arcLeadTimeCost
    end
    return totalCost
end