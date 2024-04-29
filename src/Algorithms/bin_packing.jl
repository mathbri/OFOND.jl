# Bin packing functions

# TODO : add other bin packing computations to improve this neighborhood

# TODO : adapt all files using bin packing functions the the new Bin structure, new tentative function and new update solution 

# Packing functions

function first_fit_decreasing!(
    bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity}; sorted::Bool=false
)
    # Sorting commodities in decreasing order of size (if not already done)
    if !sorted
        sort!(commodities; by=com -> com.size, rev=true)
    end
    # Adding commodities on top of others
    for commodity in commodities
        added = false
        for bin in bins
            add!(bin, commodity) && (added = true; break)
        end
        added || push!(bins, Bin(fullCapacity, commodity))
    end
end

# First fit decreasing but returns a copy of the bins instead of modifying it
function first_fit_decreasing(
    bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity}; sorted::Bool=false
)
    newBins = deepcopy(bins)
    first_fit_decreasing!(newBins, fullCapacity, commodities; sorted=sorted)
    return newBins
end

# First fit decreasing to update loads
function first_fit_decreasing!(
    loads::Vector{Int},
    fullCapacity::Int,
    commodities::Vector{Commodity};
    sorted::Bool=false,
)
    # Sorting commodities in decreasing order of size (if not already done)
    if !sorted
        sort!(commodities; by=com -> com.size, rev=true)
    end
    # Adding commodities on top of others
    for commodity in commodities
        added = false
        for (idxL, load) in enumerate(loads)
            (fullCapacity - load >= commodity.size) &&
                (added = true; loads[idxL] += commodity.size; break)
        end
        added || push!(loads, fullCapacity - commodity.size)
    end
end

# Compute the number of bins that would be added if all the commodities were packed
function tentative_first_fit(
    bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity}; sorted::Bool=false
)
    newLoads = map(bin -> bin.load, bins)
    lengthBefore = length(newLoads)
    first_fit_decreasing!(newLoads, fullCapacity, commodities; sorted=sorted)
    return length(newLoads) - lengthBefore
end

# Only useful for best fit decreasing computation of best bin
function get_capacity_left(bin::Bin, commodity::Commodity)
    capacity_after = bin.capacity - commodity.size
    capacity_after < 0 && return INFINITY
    return capacity_after
end

# Best fit decreasing heuristic for bin packing
function best_fit_decreasing!(
    bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity}; sorted::Bool=false
)
    # Sorting commodities in decreasing order of size (if not already done)
    sorted || sort!(commodities; by=com -> com.size, rev=true)
    # Adding commodities on top of others
    for commodity in commodities
        # Selecting best bin
        bestCapa, bestBin = findmin(bin -> get_capacity_left(bin, commodity), possibleBins)
        # If the best bin is full, adding a bin
        bestCapa == INFINITY && (push!(bins, Bin(fullCapacity, commodity)); continue)
        # Otherwise, adding it to the best bin
        add!(bin[bestBin], commodity)
    end
end

# Best fit decreasing but returns a copy of the bins instead of modifying it
function best_fit_decreasing(
    bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity}; sorted::Bool=false
)
    newBins = deepcopy(bins)
    best_fit_decreasing!(newBins, fullCapacity, commodities; sorted=sorted)
    return newBins
end

# Milp model for adding commodities on top
function milp_packing!(bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity})
    n = length(commodities)
    loads = map(bin -> bin.load, bins)
    B = length(first_fit_decreasing(loads, fullCapacity, commodities))
    # Model
    model = Model(HiGHS.Optimizer)
    # Variables
    @variable(model, x[1:n, 1:B], Bin)
    @variable(model, y[1:B], Bin)
    # Constraints
    @constraint(model, inBin[i=1:n], sum(x[i, :]) == 1)
    @constraint(
        model,
        fitInBin[b=1:B],
        fullCapacity * y[b] >= sum(x[i, b] * commodities[i].size for i in 1:n) + loads[b]
    )
    # Objective
    @objective(model, Min, sum(y))
    # Solve
    optimize!(model)
    # Get variables value
    yval = value.(model[:y])
    xval = value.(model[:x])
    # Add new bins if necessary
    for b in length(bins):B
        yval[b] == 1 && push!(bins, Bin(fullCapacity))
    end
    # Add commodities to bins
    for i in 1:n, b in 1:B
        xval[i, b] == 1 && add!(bins[b], commodities[i])
    end
end

function milp_packing(bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity})
    newBins = deepcopy(bins)
    milp_packing!(newBins, fullCapacity, commodities)
    return newBins
end

# Updating functions that uses bin packing

# TODO : add current_cost option for this all all other functions
function compute_new_cost(
    arcData::NetworkArc, dstData::NetworkNode, newBins::Int, commodities::Vector{Commodity}
)
    volume = sum(com.size for com in commodities) / VOLUME_FACTOR
    leadTimeCost = sum(com.leadTimeCost for com in commodities)
    # Node cost 
    cost = (dstData.volumeCost + arcData.carbonCost) * volume
    # Transport cost 
    cost += newBins * arcData.unitCost
    # Commodity cost
    return cost += arcData.distance * leadTimeCost
end

# Add order content to solution truck loads with packing function
function add_order!(
    solution::Solution,
    TSGraph::TimeSpaceGraph,
    timedPath::Vector{Int},
    order::Order;
    sorted::Bool=false,
)
    costAdded = 0.0
    for (timedSrc, timedDst) in partition(timedPath, 2, 1)
        bins = solution.bins[timedSrc, timedDst]
        dstData = TSGraph.networkNodes[timedDst]
        arcData = TSGraph.networkArcs[timedSrc, timedDst]
        fullCapa, binsBefore = arcData.capacity, length(bins)
        # Updating bins
        first_fit_decreasing!(bins, fullCapa, order.content; sorted=sorted)
        # Updating cost
        newBins = length(bins) - binsBefore
        costAdded += compute_new_cost(arcData, dstData, newBins, order.content)
    end
    return costAdded
end

# Remove order content from solution truck loads, does not refill bins
function remove_order!(
    solution::Solution, TSGraph::TimeSpaceGraph, timedPath::Vector{Int}, order::Order;
)
    costAdded, orderUniqueCom = 0.0, unique(order.content)
    # For all arcs in the path, updating the right bins
    for (timedSrc, timedDst) in partition(timedPath, 2, 1)
        for bin in solution.bins[timedSrc, timedDst]
            remove!(bin, orderUniqueCom)
        end
        dstData = TSGraph.networkNodes[timedDst]
        arcData = TSGraph.networkArcs[timedSrc, timedDst]
        costAdded -= compute_new_cost(arcData, dstData, 0, order.content)
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
)
    costAdded = 0.0
    for order in bundle.orders
        # Projecting path
        timedPath = time_space_projector(TTGraph, TSGraph, path, order.deliveryDate)
        # Add or Remove order
        if remove
            costAdded += remove_order!(solution, TSGraph, timedPath, order)
        else
            costAdded += add_order!(solution, TSGraph, timedPath, order; sorted=sorted)
        end
    end
    return costAdded
end

# TODO : return cost added by the intro (> 0) or removal (< 0) ? but you want to refill the bins only after removing all bundles
# Add a function add_bundle to mimic remove bundle
# Keep only the update solution with vectors
# Refill bins in the remove case and compute cost added for both

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
    allCommodities = reduce(vcat, bins)
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
    # TODO : Remove path from bundlePaths and bundle on nodes
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