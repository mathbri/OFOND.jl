# Bin packing functions

function first_fit_decreasing(bins::Vector{Bin}, capacity::Int, commodities::Vector{Commodity}; sorted::Bool=false)
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

function best_fit_decreasing(bins::Vector{Bin}, capacity::Int, commodities::Vector{Commodity}; sorted::Bool=false)
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

function milp_packing()
    
end

# TODO : to implement for V0
# Local search where path are fixed and bin-packing are optimized again
function bin_packing_local_search()
    
end