# Utils function for the large neighborhood search

# For arcs in the time-space network :
#     Update the current cost with the following mechanism :
#         Compute an actual volume cost : volume_cost = (unit_cost * nb_of_units) / total_volume_in_units
#         Compute the updated unit cost : unit cost = unit_capacity * volume_cost
# Use this new costs in all the other heuristics

function slope_scaling_cost_update!(timeSpaceGraph::TimeSpaceGraph)
    for arc in edges(timeSpaceGraph.graph)
        arcData = timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        # Total volume on arc
        arcVolume = sum(arcData.capacity - bin.availableCapacity for bin in arcBins)
        # All arc bins
        arcBins = timeSpaceGraph.bins[src(arc), dst(arc)]
        # Updating current cost
        baseCost = (arcData.unitCost + arcData.carbonCost)
        costFactor = length(arcBins) * arcData.capacity / arcVolume
        timeSpaceGraph.currentCost[src(arc), dst(arc)] = baseCost * costFactor
    end
end

# At least a function to build the milp based on the bundles
# Could be good idea to have a function if there is one point (plant neighbor) and two nodes (two node neighbor or attract reduce neighbor)