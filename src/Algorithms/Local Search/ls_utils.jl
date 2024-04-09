# Utils function for local search neighborhoods

# TODO : when solution struct updated, replace paths with solution and get path with the bundle idx
# Combine all bundles paths in arguments into a sparse matrix indicating the arcs to work with
function get_bundles_time_space_arcs(
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

# Store previous bins before removing commodities from them
function save_previous_bins(
    timeSpaceGraph::TimeSpaceGraph, workingArcs::SparseMatrixCSC{Bool,Int}
)
    previousCost = 0.0
    I, J, _ = findnz(workingArcs)
    oldBins = Vector{Vector{Bin}}(undef, length(workingArcs))
    # Efficient iteration over sparse matrices
    rows = rowvals(workingArcs)
    for timedDst in 1:size(workingArcs, 2)
        for srcIdx in nzrange(workingArcs, timedDst)
            timedSrc = rows[srcIdx]
            # Adding previous arc cost
            previousCost += compute_arc_cost(timeSpaceGraph, timedSrc, timedDst)
            # Storing old bins
            oldBins[srcIdx] = timeSpaceGraph.bins[timedSrc, timedDst]
        end
    end
    return sparse(I, J, oldBins), previousCost
end

# Revert the bin loading the the vector of bins given
function revert_bins!(
    timeSpaceGraph::TimeSpaceGraph, previousBins::SparseMatrixCSC{Vector{Bin},Int}
)
    # Efficient iteration over sparse matrices
    rows = rowvals(previousBins)
    eachindex()
    for timedDst in 1:size(previousBins, 2)
        for srcIdx in nzrange(previousBins, timedDst)
            timedSrc = rows[srcIdx]
            # Reverting to previous bins
            timeSpaceGraph.bins[timedSrc, timedDst] = previousBins[timedSrc, timedDst]
        end
    end
end

# TODO : check to see if computing the unique commodities is costful and if the projection here also
# Remove order content from solution truck loads
function remove_bundles!(
    timeSpaceGraph::TimeSpaceGraph,
    travelTimeGraph::TravelTimeGraph,
    bundle::Bundle,
    path::Vector{Int},
)
    # For all orders
    for order in bundle.orders
        timedPath = time_space_projector(
            travelTimeGraph, timeSpaceGraph, path, order.deliveryDate
        )
        orderUniqueCom = unique(order.content)
        # For all arcs in the path, updating the right bins
        for (timedSrc, timedDst) in partition(timedPath, 2, 1)
            for bin in timeSpaceGraph.bins[timedSrc, timedDst]
                filter!(com -> com in orderUniqueCom, bin.content)
            end
        end
    end
end

function remove_bundles!(
    timeSpaceGraph::TimeSpaceGraph,
    travelTimeGraph::TravelTimeGraph,
    bundles::Vector{Bundle},
    paths::Vector{Vector{Int}},
)
    for (bundle, path) in zip(bundles, paths)
        remove_bundles!(timeSpaceGraph, travelTimeGraph, bundle, path)
    end
end

function refill_bins!(
    timeSpaceGraph::TimeSpaceGraph, workingArcs::SparseMatrixCSC{Bool,Int}
)
    costAfterRefill = 0.0
    # Efficient iteration over sparse matrices
    rows = rowvals(workingArcs)
    for timedDst in 1:size(workingArcs, 2)
        for srcIdx in nzrange(workingArcs, timedDst)
            timedSrc = rows[srcIdx]
            # Cathering all remaining commodities than emptying bins
            allCommodities = reduce(vcat, timeSpaceGraph.bins[timedSrc, timedDst])
            empty!(timeSpaceGraph.bins[timedSrc, timedDst])
            # Filling it back again
            first_fit_decreasing!(
                timeSpaceGraph.bins[timedSrc, timedDst],
                timeSpaceGraph.networkArcs[timedSrc, timedDst].capacity,
                allCommodities;
                sorted=false,
            )
            # Adding new arc cost
            costAfterRefill += compute_arc_cost(timeSpaceGraph, timedSrc, timedDst)
        end
    end
    return costAfterRefill
end

function select_two_nodes(travelTimeGraph::TravelTimeGraph)
    node1 = rand(keys(travelTimeGraph.bundlesOnNodes))
    node2 = rand(keys(travelTimeGraph.bundlesOnNodes))
    while node1 == node2
        node2 = rand(keys(travelTimeGraph.bundlesOnNodes))
    end
    return node1, node2
end

function get_bundles_to_update(travelTimeGraph::TravelTimeGraph, node1::Int, node2::Int=-1)
    node2 == -1 && return travelTimeGraph.bundlesOnNodes[node1]
    return intersect(
        travelTimeGraph.bundlesOnNodes[node1], travelTimeGraph.bundlesOnNodes[node2]
    )
end

function update_bundle_paths!(
    bundlePaths::Vector{Vector{Int}},
    src::Int,
    dst::Int,
    bundles::Vector{Bundle},
    paths::Vector{Vector{Int}},
)
    for bundle in bundles
        bundlePath = bundlePaths[bundle.idx]
        srcIdx = findfirst(node -> node == src, bundlePath)
        dstIdx = findlast(node -> node == dst, bundlePath)
        bundlePaths[bundle.idx] = vcat(
            bundlePath[1:srcIdx], paths[bundle.idx][2:(end - 1)], bundlePath[dstIdx:end]
        )
    end
end