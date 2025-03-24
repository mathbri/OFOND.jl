# Updating functions for the bins

function compute_new_cost(
    arcData::NetworkArc, dstData::NetworkNode, newBins::Int, commodities::Vector{Commodity}
)
    volume = sum(com.size for com in commodities)
    leadTimeCost = sum(com.stockCost for com in commodities)
    # Node cost 
    cost =
        dstData.volumeCost * volume / VOLUME_FACTOR +
        arcData.carbonCost * volume / arcData.volumeCapacity
    # Transport cost 
    addedBins = arcData.isLinear ? (volume / arcData.volumeCapacity) : newBins
    return cost += addedBins * arcData.unitCost
    # Commodity cost
    # return cost += arcData.distance * leadTimeCost
end

# Add order content to solution truck loads with packing function
function add_order!(
    solution::Solution,
    TSGraph::TimeSpaceGraph,
    timedPath::Vector{Int},
    order::Order;
    sorted::Bool=false,
    verbose::Bool=false,
)
    costAdded = 0.0
    verbose && println("\nAdding order $(order) on timed path $timedPath")
    for (timedSrc, timedDst) in partition(timedPath, 2, 1)
        verbose && println("\nAdding on arc $timedSrc -> $timedDst")
        bins = solution.bins[timedSrc, timedDst]
        dstData = TSGraph.networkNodes[timedDst]
        arcData = TSGraph.networkArcs[timedSrc, timedDst]
        verbose && println("Dst node $timedDst : $(dstData)")
        verbose && println("Arc $timedSrc -> $timedDst : $(arcData)")
        previousLoads = [bin.volumeLoad for bin in bins]
        verbose &&
            println("Bins : $(length(bins)) -> $([bin.volumeLoad for bin in bins]) m3")
        # Updating bins
        addedBins = first_fit_decreasing!(bins, arcData, order; sorted=sorted)
        verbose && println("Order added : $addedBins new bins")
        if length(previousLoads) < length(bins)
            append!(previousLoads, zeros(length(bins) - length(previousLoads)))
        end
        verbose && println(
            "Bins : $(length(bins)) -> $([bin.volumeLoad for bin in bins] .- previousLoads) m3",
        )
        verbose &&
            println("Bins : $(length(bins)) -> $([bin.volumeLoad for bin in bins]) m3")
        # Updating cost
        costAddedForOrder = compute_new_cost(arcData, dstData, addedBins, order.content)
        verbose && println("Cost added for order : $costAddedForOrder")
        costAdded += compute_new_cost(arcData, dstData, addedBins, order.content)
    end
    return costAdded
end

# Remove order content from solution truck loads, does not refill bins
function remove_order!(
    solution::Solution,
    TSGraph::TimeSpaceGraph,
    timedPath::Vector{Int},
    order::Order;
    verbose::Bool=false,
)
    costAdded, orderUniqueCom = 0.0, unique(order.content)
    verbose && println("\nRemoving order $(order) on timed path $timedPath")
    # For all arcs in the path, updating the right bins
    for (timedSrc, timedDst) in partition(timedPath, 2, 1)
        verbose && println("\nRemoving on arc $timedSrc -> $timedDst")
        arcBins = solution.bins[timedSrc, timedDst]
        previousLoads = [bin.volumeLoad for bin in arcBins]
        verbose && println(
            "Bins : $(length(arcBins)) -> $([bin.volumeLoad for bin in arcBins]) m3"
        )
        for bin in solution.bins[timedSrc, timedDst]
            remove!(bin, orderUniqueCom)
        end
        verbose && println("Order removed")
        verbose && println(
            "Bins : $(length(arcBins)) -> $([bin.volumeLoad for bin in arcBins] .- previousLoads) m3",
        )
        verbose && println(
            "Bins : $(length(arcBins)) -> $([bin.volumeLoad for bin in arcBins]) m3"
        )
        dstData = TSGraph.networkNodes[timedDst]
        verbose && println("Dst Node $timedDst : $(dstData)")
        arcData = TSGraph.networkArcs[timedSrc, timedDst]
        verbose && println("Arc $timedSrc -> $timedDst : $(arcData)")
        costRemoved = compute_new_cost(arcData, dstData, 0, order.content)
        verbose && println("Cost removed : $costRemoved")
        costAdded -= compute_new_cost(arcData, dstData, 0, order.content)
        verbose && println("Total cost added : $costAdded")
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
    verbose::Bool=false,
)
    costAdded = 0.0
    verbose && println(
        "\nUpdating bins for bundle $bundle (bunH = $(bundle.hash) on path travel time path $path",
    )
    for order in bundle.orders
        verbose && println("Updating order $order")
        # Projecting path
        timedPath = time_space_projector(TTGraph, TSGraph, path, order)
        verbose && println("Timed path : $timedPath")
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
            verbose && println("\nRemoving order $(order)")
            costAdded += remove_order!(solution, TSGraph, timedPath, order; verbose=verbose)
            verbose && println("Cost removed : $costAdded")
        else
            verbose && println("\nAdding order $(order)")
            costAdded += add_order!(
                solution, TSGraph, timedPath, order; sorted=sorted, verbose=verbose
            )
            verbose && println("Cost added for order : $costAdded")
        end
    end
    return costAdded
end

function update_arc_bins!(
    solution::Solution,
    TSGraph::TimeSpaceGraph,
    TTGraph::TravelTimeGraph,
    bundle::Bundle,
    src::Int,
    dst::Int;
    sorted::Bool=true,
    verbose::Bool=false,
)
    arcUpdateCost = 0.0
    verbose && println("\nAdding on arc $src -> $dst")
    for order in bundle.orders
        verbose && println("\nUpdating order $order")
        # Projecting path
        timedSrc, timedDst = time_space_projector(TTGraph, TSGraph, src, dst, order)
        verbose && println("Timed projection $timedSrc -> $timedDst")
        # Add order (only add for now)
        bins = solution.bins[timedSrc, timedDst]
        dstData = TSGraph.networkNodes[timedDst]
        arcData = TSGraph.networkArcs[timedSrc, timedDst]
        verbose && println("Dst node $timedDst : $(dstData)")
        verbose && println("Arc $timedSrc -> $timedDst : $(arcData)")
        previousLoads = [bin.volumeLoad for bin in bins]
        verbose &&
            println("Bins : $(length(bins)) -> $([bin.volumeLoad for bin in bins]) m3")
        # Updating bins
        addedBins = first_fit_decreasing!(bins, arcData, order; sorted=sorted)
        verbose && println("Order added : $addedBins new bins")
        if length(previousLoads) < length(bins)
            append!(previousLoads, zeros(length(bins) - length(previousLoads)))
        end
        verbose && println(
            "Bins : $(length(bins)) -> $([bin.volumeLoad for bin in bins] .- previousLoads) m3",
        )
        verbose &&
            println("Bins : $(length(bins)) -> $([bin.volumeLoad for bin in bins]) m3")
        # Updating cost
        costAddedForOrder = compute_new_cost(arcData, dstData, addedBins, order.content)
        verbose && println("Cost added for order : $costAddedForOrder")
        arcUpdateCost += costAddedForOrder
        verbose && println("arcUpdateCost = $arcUpdateCost")
    end
    return arcUpdateCost
end

function update_bins2!(
    solution::Solution,
    TSGraph::TimeSpaceGraph,
    TTGraph::TravelTimeGraph,
    bundle::Bundle,
    path::Vector{Int};
    sorted::Bool=false,
    remove::Bool=false,
    verbose::Bool=false,
)
    costAdded = 0.0
    verbose && println(
        "\nUpdating bins for bundle $bundle (bunH = $(bundle.hash) on path travel time path $path",
    )
    for (src, dst) in partition(path, 2, 1)
        arcUpdateCost = 0.0
        verbose && println("\nAdding on arc $src -> $dst")
        for order in bundle.orders
            verbose && println("\nUpdating order $order")
            # Projecting path
            timedSrc, timedDst = time_space_projector(TTGraph, TSGraph, src, dst, order)
            verbose && println("Timed projection $timedSrc -> $timedDst")
            # Add order (only add for now)
            bins = solution.bins[timedSrc, timedDst]
            dstData = TSGraph.networkNodes[timedDst]
            arcData = TSGraph.networkArcs[timedSrc, timedDst]
            verbose && println("Dst node $timedDst : $(dstData)")
            verbose && println("Arc $timedSrc -> $timedDst : $(arcData)")
            previousLoads = [bin.volumeLoad for bin in bins]
            verbose &&
                println("Bins : $(length(bins)) -> $([bin.volumeLoad for bin in bins]) m3")
            # Updating bins
            addedBins = first_fit_decreasing!(bins, arcData, order; sorted=sorted)
            verbose && println("Order added : $addedBins new bins")
            if length(previousLoads) < length(bins)
                append!(previousLoads, zeros(length(bins) - length(previousLoads)))
            end
            verbose && println(
                "Bins : $(length(bins)) -> $([bin.volumeLoad for bin in bins] .- previousLoads) m3",
            )
            verbose &&
                println("Bins : $(length(bins)) -> $([bin.volumeLoad for bin in bins]) m3")
            # Updating cost
            costAddedForOrder = compute_new_cost(arcData, dstData, addedBins, order.content)
            verbose && println("Cost added for order : $costAddedForOrder")
            arcUpdateCost += costAddedForOrder
            verbose && println("\n Arc update cost : $arcUpdateCost")
            costAdded += costAddedForOrder
        end
    end
    return costAdded
end