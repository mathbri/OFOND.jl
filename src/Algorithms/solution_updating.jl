# Updating functions for the solution

# TODO : could be merged with add_path function
function is_path_partial(TTGraph::TravelTimeGraph, bundle::Bundle, path::Vector{Int};)
    bundle.supplier != TTGraph.networkNodes[path[1]] && return true
    bundle.customer != TTGraph.networkNodes[path[end]] && return true
    return false
end

function remove_shortcuts!(path::Vector{Int}, travelTimeGraph::TravelTimeGraph)
    firstNode = 1
    for (src, dst) in partition(path, 2, 1)
        if travelTimeGraph.networkArcs[src, dst].type == :shortcut
            firstNode += 1
        else
            break
        end
    end
    return deleteat!(path, 1:(firstNode - 1))
end

function add_bundle!(
    solution::Solution,
    instance::Instance,
    bundle::Bundle,
    path::Vector{Int};
    sorted::Bool=false,
    skipFill::Bool=false,
)
    # If nothing to do, returns nothing
    length(path) == 0 && return 0.0
    TSGraph, TTGraph = instance.timeSpaceGraph, instance.travelTimeGraph
    # Adding the bundle to the solution
    remove_shortcuts!(path, TTGraph)
    add_path!(solution, bundle, path; partial=is_path_partial(TTGraph, bundle, path))
    # Updating the bins
    skipFill && return 0.0
    return update_bins!(solution, TSGraph, TTGraph, bundle, path; sorted=sorted)
end

# TODO : consider BitArray as it contains only boolean values
# Combine all bundles paths in arguments into a sparse matrix indicating the arcs to work with
function get_bins_updated(
    TSGraph::TimeSpaceGraph,
    TTGraph::TravelTimeGraph,
    bundles::Vector{Bundle},
    paths::Vector{Vector{Int}},
)
    I, J = Int[], Int[]
    # For every bundle path and every order in the bundle, adding the timed nodes in the matrix indices
    for (bundle, path) in zip(bundles, paths)
        for order in bundle.orders
            timedPath = time_space_projector(TTGraph, TSGraph, path, order)
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
    TSGraph::TimeSpaceGraph,
    workingArcs::SparseMatrixCSC{Bool,Int};
    current_cost::Bool=false,
)
    costAdded = 0.0
    # Efficient iteration over sparse matrices
    rows = rowvals(workingArcs)
    for tDst in 1:Base.size(workingArcs, 2)
        for srcIdx in nzrange(workingArcs, tDst)
            tSrc = rows[srcIdx]
            arcData = TSGraph.networkArcs[tSrc, tDst]
            # No need to refill bins on linear arcs
            arcData.isLinear && continue
            # Adding new bins cost
            costAdded +=
                refill_bins!(solution.bins[tSrc, tDst], arcData.capacity) * arcData.unitCost
        end
    end
    return costAdded
end

# TODO : adapt test to this new return
# Remove the bundle only on the path portion provided
function remove_bundle!(
    solution::Solution,
    instance::Instance,
    bundle::Bundle,
    path::Vector{Int};
    sorted::Bool=false,
)
    TSGraph, TTGraph = instance.timeSpaceGraph, instance.travelTimeGraph
    oldPart = Int[]
    if length(path) == 0 || !is_path_partial(TTGraph, bundle, path)
        oldPart = remove_path!(solution, bundle)
    else
        oldPart = remove_path!(solution, bundle; src=path[1], dst=path[end])
    end
    if oldPart == [-1, -1]
        println("Error in removing the bundle")
        println("Bundle : $bundle")
        println("Path : $path")
    end
    costRemoved = update_bins!(
        solution, TSGraph, TTGraph, bundle, oldPart; sorted=sorted, remove=true
    )
    return (costRemoved, oldPart)
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
    skipRefill::Bool=false,
)
    costAdded = 0.0
    if !remove
        # If remove = false, adding the bundle to the solution
        for (bundle, path) in zip(bundles, paths)
            costAdded += add_bundle!(
                solution, instance, bundle, path; sorted=sorted, skipFill=skipRefill
            )
            println("Cost added : $costAdded")
        end
    else
        pathsToUpdate = Vector{Vector{Int}}()
        # If remove = true, removing the bundle from the solution
        for (bundle, path) in zip(bundles, paths)
            costRemoved, oldPart = remove_bundle!(
                solution, instance, bundle, path; sorted=sorted
            )
            costAdded += costRemoved
            push!(pathsToUpdate, oldPart)
            println("Cost removed : $costAdded")
        end
        # If skipRefill than no recomputation
        skipRefill && return costAdded
        # Than refilling the bins
        binsUpdated = get_bins_updated(
            instance.timeSpaceGraph, instance.travelTimeGraph, bundles, pathsToUpdate
        )
        I, J, V = findnz(binsUpdated)
        println("Bins updated : \n $I \n $J")
        I, J, V = findnz(solution.bins)
        println("Bins before refilling : \n $I \n $J \n $V")
        costAdded += refill_bins!(solution, instance.timeSpaceGraph, binsUpdated)
        println("Cost refilled : $costAdded")
    end
    return costAdded
end

# Removing all empty bins from the linear arcs (to be used before extraction)
function clean_empty_bins!(solution::Solution, instance::Instance)
    TSGraph = instance.timeSpaceGraph
    for arc in edges(TSGraph.graph)
        arcData = TSGraph.networkArcs[src(arc), dst(arc)]
        # No update for consolidated arcs
        !arcData.isLinear && continue
        # Removing empty bins
        filter!(bin -> bin.load > 0, solution.bins[src(arc), dst(arc)])
    end
end