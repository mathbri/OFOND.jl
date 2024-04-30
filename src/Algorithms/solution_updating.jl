# Updating functions for the solution

function add_bundle!(
    solution::Solution,
    instance::Instance,
    bundle::Bundle,
    path::Vector{Int};
    sorted::Bool=false,
)
    # If nothing to do, returns nothing
    length(path) == 0 && return costAdded
    TSGraph, TTGraph = instance.timeSpaceGraph, instance.travelTimeGraph
    # Adding the bundle to the solution
    remove_shortcuts!(path, TTGraph)
    add_path!(solution, bundle, path)
    # Updating the bins
    return update_bins!(solution, TSGraph, TTGraph, bundle, path; sorted=sorted)
end

# TODO : consider BitArray as it contains only boolean values
# Combine all bundles paths in arguments into a sparse matrix indicating the arcs to work with
function get_bins_updated(
    timeSpaceGraph::TimeSpaceGraph,
    travelTimeGraph::TravelTimeGraph,
    bundles::Vector{Bundle},
    paths::Vector{Vector{Int}},
)
    I, J = Int[], Int[]
    # For every bundle path and every order in the bundle, adding the timed nodes in the matrix indices
    for (bundle, path) in zip(bundles, paths)
        for order in bundle.orders
            timedPath = time_space_projector(
                travelTimeGraph, timeSpaceGraph, path, order.deliveryDate
            )
            # Without checking overlapping as the combine function will take care of it
            append!(I, timedPath[1:(end - 1)])
            append!(J, timedPath[2:end])
        end
    end
    V = ones(Bool, length(I))
    # Combine function for bools is | by default
    return sparse(I, J, V)
end

function refill_bins!(bins::Vector{Bin}, fullCapacity::Int)
    allCommodities = get_all_commodities(bins)
    binsBefore = length(bins)
    empty!(bins)
    # Filling it back again
    first_fit_decreasing!(bins, fullCapacity, allCommodities; sorted=false)
    return length(bins) - binsBefore
end

# Refill bins on the working arcs, to be used after bundle removal
function refill_bins!(
    solution::Solution,
    timeSpaceGraph::TimeSpaceGraph,
    workingArcs::SparseMatrixCSC{Bool,Int};
    current_cost::Bool=false,
)
    costAdded = 0.0
    # Efficient iteration over sparse matrices
    rows = rowvals(workingArcs)
    for timedDst in 1:size(workingArcs, 2)
        for srcIdx in nzrange(workingArcs, timedDst)
            timedSrc = rows[srcIdx]
            arcData = timeSpaceGraph.networkArcs[timedSrc, timedDst]
            # No need to refill bins on linear arcs
            arcData.isLinear && continue
            bins = solution.bins[timedSrc, timedDst]
            newBins = refill_bins!(bins, arcData)
            # Adding new arc cost
            costAdded += newBins * arcData.unitCost
        end
    end
    return costAfterRefill
end

# Remove the bundle only on the path portion provided
function remove_bundle!(
    solution::Solution,
    instance::Instance,
    bundle::Bundle,
    path::Vector{Int};
    sorted::Bool=false,
)
    TSGraph, TTGraph = instance.timeSpaceGraph, instance.travelTimeGraph
    remove_path!(solution, bundle; src=path[1], dst=path[end])
    return update_bins!(
        solution, TSGraph, TTGraph, bundle, path; sorted=sorted, remove=true
    )
end

# Update the current solution
# Providing a path with remove option means to remove the bundle only on the path portion provided
function update_solution!(
    solution::Solution,
    instance::Instance,
    bundles::Vector{Bundle},
    paths::Vector{Vector{Int}}=[Int[] for _ in 1:length(bundles)];
    remove::Bool=false,
    sorted::Bool=false,
)
    costAdded = 0.0
    if !remove
        # If remove = false, adding the bundle to the solution
        for (bundle, path) in zip(bundles, paths)
            costAdded += add_bundle!(solution, instance, bundle, path; sorted=sorted)
        end
    else
        # If remove = true, removing the bundle from the solution
        for (bundle, path) in zip(bundles, paths)
            costAdded += remove_bundle!(solution, instance, bundle, path; sorted=sorted)
        end
        # Than refilling the bins
        binsUpdated = get_bins_updated(
            instance.timeSpaceGraph, instance.travelTimeGraph, bundles, paths
        )
        costAdded += refill_bins!(solution, instance.timeSpaceGraph, binsUpdated)
    end
    return costAdded
end