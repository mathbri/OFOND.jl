# Bin packing functions

function first_fit_decreasing!(bins::Vector{Bin}, capacity::Int, commodities::Vector{Commodity}; sorted::Bool=false)
    # Sorting commodities in decreasing order of size (if not already done)
    if !sorted
        sort!(commodities, by=com -> com.size, rev=true)        
    end
    # Adding commodities on top of others
    for commodity in commodities
        added = false
        for bin in bins
            add!(bin, commodity) && (added = true; break)
        end
        added || push!(bins, Bin(capacity - commodity.size, [commodity]))
    end
end

# First fit decreasing but returns a copy of the bins instead of modifying it
function first_fit_decreasing(bins::Vector{Bin}, capacity::Int, commodities::Vector{Commodity}; sorted::Bool=false)
    newBins = deepcopy(bins)
    first_fit_decreasing!(newBins, capacity, commodities; sorted=sorted)
    return newBins
end

function best_fit_decreasing!(bins::Vector{Bin}, capacity::Int, commodities::Vector{Commodity}; sorted::Bool=false)
    # Sorting commodities in decreasing order of size (if not already done)
    if !sorted
        sort!(commodities, by=com -> com.size, rev=true)        
    end
    # Storing last size seen to avoid recomputing possible bins
    lastSizeSeen = commodities[1].size
    possibleBins = filter(bin -> bin.availableCapacity - commodity.size >= 0, bins)
    # Adding commodities on top of others
    for commodity in commodities
        # Filtering bins with enough space (if needed)
        if commodity.size != lastSizeSeen
            possibleBins = filter(bin -> bin.availableCapacity - commodity.size >= 0, bins)
            lastSizeSeen = commodity.size
        end
        # If no bins, adding one and continuing to the next commodity
        length(possibleBins) == 0 && (push!(bins, Bin(capacity - commodity.size, [commodity])); continue)
        # Selecting best bin
        _, bestBin = findmin(bin -> bin.availableCapacity - commodity.size, possibleBins)
        add!(bin[bestBin], commodity)
    end
end

# Best fit decreasing but returns a copy of the bins instead of modifying it
function best_fit_decreasing(bins::Vector{Bin}, capacity::Int, commodities::Vector{Commodity}; sorted::Bool=false)
    newBins = deepcopy(bins)
    best_fit_decreasing!(newBins, capacity, commodities; sorted=sorted)
    return newBins
end

# TODO : copy from Louis
function milp_packing()
    #
end

# Improving all bin packings if possible
function bin_packing_improvement!(timeSpaceGraph::TimeSpaceGraph; sorted::Bool=false, skipLinear::Bool=true)
    costImprov = 0.
    for arc in edges(timeSpaceGraph)
        arcBins = timeSpaceGraph.bins[src(arc), dst(arc)]
        # If there is no bins, one bin or the arc is linear, skipping arc
        length(arcBins) <= 1 && continue
        arcData = timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        skipLinear && arcData.isLinear && continue
        # If there is no gap with the lower bound, skipping arc
        arcVolume = sum(arcData.capacity - bin.availableCapacity for bin in arcBins)
        ceil(arcVolume / arcData.capacity) == length(arcBins) && continue
        # Gathering all commodities
        allCommodities = reduce(vcat, arcBins)
        # Computing new bins
        newBins = first_fit_decreasing(Bin[], arcData.capacity, allCommodities, sorted=sorted)
        bfdBins = best_fit_decreasing(Bin[], arcData.capacity, allCommodities, sorted=sorted)
        length(newBins) > length(bfdBins) && (newBins = bfdBins)
        # If the number of bins did not change, skipping next
        length(newBins) >= length(arcBins) && continue
        # Computing cost improvement
        costImprov += (arcData.unitCost + arcData.carbonCost) * (length(arcBins) - length(newBins))
        # Updating bins
        timeSpaceGraph.bins[src(arc), dst(arc)] = newBins
    end
    return costImprov
end

# Running bin packing improvement with analysis logging and no change in data
function bin_packing_improvement_analysis(timeSpaceGraph::TimeSpaceGraph)
    costImprov = 0.
    oneBinCount, linearCount, boudReachedCount = 0, 0, 0
    bfdBetterCount, bfdSavedBins, newBetterCount = 0, 0, 0
    for arc in edges(timeSpaceGraph)
        arcBins = timeSpaceGraph.bins[src(arc), dst(arc)]
        # If there is no bins, one bin or the arc is linear, skipping arc
        if length(arcBins) <= 1
            oneBinCount += 1
            continue
        end
        arcData = timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        if arcData.isLinear
            linearCount += 1
            continue
        end
        # If there is no gap with the lower bound, skipping arc
        arcVolume = sum(arcData.capacity - bin.availableCapacity for bin in arcBins)
        if ceil(arcVolume / arcData.capacity) == length(arcBins)
            boudReachedCount += 1
            continue
        end
        # Gathering all commodities
        allCommodities = reduce(vcat, arcBins)
        # Computing new bins
        newBins = first_fit_decreasing(Bin[], arcData.capacity, allCommodities, sorted=sorted)
        bfdBins = best_fit_decreasing(Bin[], arcData.capacity, allCommodities, sorted=sorted)
        if length(newBins) > length(bfdBins) 
            bfdSavedBins = length(newBins) - length(bfdBins)
            newBins = bfdBins
            bfdBetterCount += 1
        end
        # If the number of bins dir not change, skipping next
        if length(newBins) >= length(arcBins) 
            continue
        end
        newBetterCount += 1
        # Computing cost improvement
        costImprov += (arcData.unitCost + arcData.carbonCost) * (length(arcBins) - length(newBins))
    end
    println("One bin count: $oneBinCount")
    println("Linear count: $linearCount")
    println("Bound reached count: $boudReachedCount")
    println("Best fit decrease better count: $bfdBetterCount")
    println("Best fit decrease saved bins: $bfdSavedBins")
    println("New better count: $newBetterCount")
    return costImprov
end

function update_bins!(timeSpaceGraph::TimeSpaceGraph, travelTimeGraph::TravelTimeGraph, path::Vector{Int}, order::Order; sorted::Bool=false)
    # For all arcs in the path, updating the right bins
    for (src, dst) in partition(path, 2, 1)
        timedSrc = time_space_projector(travelTimeGraph, timeSpaceGraph, src, order.deliveryDate)
        timedDst = time_space_projector(travelTimeGraph, timeSpaceGraph, dst, order.deliveryDate)
        first_fit_decreasing!(timeSpaceGraph.bins[timedSrc, timedDst], timeSpaceGraph.networkArcs[timedSrc, timedDst].capacity, order.content, sorted=sorted)
    end
end
