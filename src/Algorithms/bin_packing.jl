# Bin packing functions

# TODO : add other bin packing computations to improve this neighborhood

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
        added || push!(bins, Bin(fullCapacity - commodity.size, [commodity]))
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

function first_fit_decreasing(
    loads::Vector{Int},
    fullCapacity::Int,
    commodities::Vector{Commodity};
    sorted::Bool=false,
)
    newLoads = deepcopy(loads)
    first_fit_decreasing!(newBins, fullCapacity, commodities; sorted=sorted)
    return length(newLoads) - length(loads)
end

# Only useful for best fit decreasing computation of best bin
function get_capacity_left(bin::Bin, commodity::Commodity)
    capcity_after = bin.capacity - commodity.size
    capcity_after < 0 && return INFINITY
    return capcity_after
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
        bestCapa == INFINITY &&
            (push!(bins, Bin(fullCapacity - commodity.size, [commodity])); continue)
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
    loads = map(bin -> fullCapacity - bin.capacity, bins)
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

function update_bins!(
    solution::Solution,
    timeSpaceGraph::TimeSpaceGraph,
    travelTimeGraph::TravelTimeGraph,
    path::Vector{Int},
    order::Order;
    sorted::Bool=false,
    bin_packing::Function=first_fit_decreasing!,
)
    # Projecting path on the time space graph
    timedPath = time_space_projector(
        travelTimeGraph, timeSpaceGraph, path, order.deliveryDate
    )
    for (timedSrc, timedDst) in partition(timedPath, 2, 1)
        fullCapa = timeSpaceGraph.networkArcs[timedSrc, timedDst].capacity
        # Updating bins
        bin_packing(
            solution.bins[timedSrc, timedDst], fullCapa, order.content; sorted=sorted
        )
        # Updating loads
        # TODO : Is it more effcient to do a first fit again or to map the new available capacities ?
        solution.binLoads[timedSrc, timedDst] = map(
            bin -> bin.availableCapacity, solution.bins[timedSrc, timedDst]
        )
    end
end

function update_bins!(
    solution::Solution,
    timeSpaceGraph::TimeSpaceGraph,
    travelTimeGraph::TravelTimeGraph,
    path::Vector{Edge},
    order::Order;
    sorted::Bool=false,
)
    return update_bins!(
        solution,
        timeSpaceGraph,
        travelTimeGraph,
        get_path_nodes(path),
        order;
        sorted=sorted,
    )
end

function refill_bins!(
    bins::Vector{Bin}, fullCapacity::Int; bin_packing::Function=first_fit_decreasing!
)
    allCommodities = reduce(vcat, bins)
    empty!(bins)
    # Filling it back again
    return bin_packing(bins, fullCapacity, allCommodities; sorted=false)
end

function refill_bins!(solution::Solution, timedSrc::Int, timedDst::Int, arcData::NetworkArc)
    # Filling bins again
    refill_bins!(solution.bins[timedSrc, timedDst], arcData.capacity)
    # Updating loads
    return solution.binLoads[timedSrc, timedDst] = map(
        bin -> bin.availableCapacity, solution.bins[timedSrc, timedDst]
    )
end

# Remove order content from solution truck loads
function remove_order!(
    solution::Solution,
    timeSpaceGraph::TimeSpaceGraph,
    travelTimeGraph::TravelTimeGraph,
    path::Vector{Int},
    order::Order;
)
    timedPath = time_space_projector(
        travelTimeGraph, timeSpaceGraph, path, order.deliveryDate
    )
    orderUniqueCom = unique(order.content)
    # For all arcs in the path, updating the right bins
    for (timedSrc, timedDst) in partition(timedPath, 2, 1)
        for bin in solution.bins[timedSrc, timedDst]
            filter!(com -> com in orderUniqueCom, bin.content)
        end
    end
end

function update_loads!(solution::Solution, workingArcs::SparseMatrixCSC{Bool,Int})
    # Efficient iteration over sparse matrices
    rows = rowvals(workingArcs)
    for timedDst in 1:size(workingArcs, 2)
        for srcIdx in nzrange(workingArcs, timedDst)
            timedSrc = rows[srcIdx]
            solution.binLoads[timedSrc, timedDst] = map(
                bin -> bin.availableCapacity, solution.bins[timedSrc, timedDst]
            )
        end
    end
end

function remove_bundles!(
    solution::Solution,
    timeSpaceGraph::TimeSpaceGraph,
    travelTimeGraph::TravelTimeGraph,
    bundles::Vector{Bundle},
    paths::Vector{Vector{Int}},
    workingArcs::SparseMatrixCSC{Bool,Int},
)
    for (bundle, path) in zip(bundles, paths)
        for order in bundle.orders
            remove_order!(solution, timeSpaceGraph, travelTimeGraph, path, order)
        end
    end
    # Update load after removing all commodities from bins
    return update_loads!(solution, workingArcs)
end