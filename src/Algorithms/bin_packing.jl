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
