# Algorithms analysis functions

# Mostly used to identify / quantify the most promosing operations in the different algorithms

# Running bin packing improvement with analysis logging and no change in data
function bin_packing_improvement_analysis(timeSpaceGraph::TimeSpaceGraph)
    costImprov = 0.0
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
        newBins = first_fit_decreasing(
            Bin[], arcData.capacity, allCommodities; sorted=sorted
        )
        bfdBins = best_fit_decreasing(
            Bin[], arcData.capacity, allCommodities; sorted=sorted
        )
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
        costImprov +=
            (arcData.unitCost + arcData.carbonCost) * (length(arcBins) - length(newBins))
    end
    println("One bin count: $oneBinCount")
    println("Linear count: $linearCount")
    println("Bound reached count: $boudReachedCount")
    println("Best fit decrease better count: $bfdBetterCount")
    println("Best fit decrease saved bins: $bfdSavedBins")
    println("New better count: $newBetterCount")
    return costImprov
end

# TODO : right the others

function bundle_reintroduction_analysis() end

function two_node_incremental_analysis() end
