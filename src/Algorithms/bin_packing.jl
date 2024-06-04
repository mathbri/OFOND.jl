# Bin packing functions

# TODO : FFD and BFD have faster implementations using binary trees 
# Need to see if bin packing remains a bottleneck by number of problems to solve or time per problem
# see Faster First Fit for algorithm
# see AVL Tree in DataStructures.jl for implementation

# TODO : add other bin packing computations to improve this neighborhood

function first_fit_decreasing!(
    bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity}; sorted::Bool=false
)
    # Sorting commodities in decreasing order of size (if not already done)
    !sorted && sort!(commodities; rev=true)
    lengthBefore = length(bins)
    # Adding commodities on top of others
    for commodity in commodities
        added = false
        for bin in bins
            added = add!(bin, commodity)
            added && break
        end
        added || push!(bins, Bin(fullCapacity, commodity))
    end
    return length(bins) - lengthBefore
end

# First fit decreasing but returns a copy of the bins instead of modifying it
function first_fit_decreasing(
    bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity}; sorted::Bool=false
)
    newBins = deepcopy(bins)
    first_fit_decreasing!(newBins, fullCapacity, commodities; sorted=sorted)
    return newBins
end

# Wrapper for objects
function first_fit_decreasing!(
    bins::Vector{Bin}, arcData::NetworkArc, order::Order; sorted::Bool=false
)
    return first_fit_decreasing!(bins, arcData.capacity, order.content; sorted=sorted)
end

# First fit decreasing computed on loads to return only the number of bins added by the vector of commodities
function tentative_first_fit(
    bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity}; sorted::Bool=false
)
    # Sorting commodities in decreasing order of size (if not already done)
    !sorted && sort!(commodities; rev=true)
    capacities = map(bin -> bin.capacity, bins)
    lengthBefore = length(capacities)
    # Adding commodities on top of others
    for commodity in commodities
        added = false
        for (idxL, capacity) in enumerate(capacities)
            if capacity >= size(commodity)
                added = true
                capacities[idxL] -= size(commodity)
                break
            end
        end
        added || push!(capacities, fullCapacity - size(commodity))
    end
    return length(capacities) - lengthBefore
end

# Wrapper for objects
function tentative_first_fit(
    bins::Vector{Bin}, arcData::NetworkArc, order::Order; sorted::Bool=false
)
    return tentative_first_fit(bins, arcData.capacity, order.content; sorted=sorted)
end

# Only useful for best fit decreasing computation of best bin
function best_fit_capacity(bin::Bin, commodity::Commodity)
    capacity_after = bin.capacity - size(commodity)
    capacity_after < 0 && return INFINITY
    return capacity_after
end

# Best fit decreasing heuristic for bin packing
function best_fit_decreasing!(
    bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity}; sorted::Bool=false
)
    # Sorting commodities in decreasing order of size (if not already done)
    !sorted && sort!(commodities; rev=true)
    # As findmin doesn't work on empty bin vectors, making one recursive call here 
    if length(bins) == 0
        push!(bins, Bin(fullCapacity, commodities[1]))
        return best_fit_decreasing!(bins, fullCapacity, commodities[2:end]; sorted=true) + 1
    end
    lengthBefore = length(bins)
    # Adding commodities on top of others
    for commodity in commodities
        # Selecting best bin
        bestCapa, bestBin = findmin(bin -> best_fit_capacity(bin, commodity), bins)
        # If the best bin is full, adding a bin
        bestCapa == INFINITY && (push!(bins, Bin(fullCapacity, commodity)); continue)
        # Otherwise, adding it to the best bin
        add!(bins[bestBin], commodity)
    end
    return length(bins) - lengthBefore
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
    n == 0 && return nothing
    lengthBefore = length(bins)
    B = lengthBefore + tentative_first_fit(bins, fullCapacity, commodities)
    loads = vcat(map(bin -> bin.load, bins), fill(0, B - length(bins)))
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
        fullCapacity * y[b] >= sum(x[i, b] * size(commodities[i]) for i in 1:n) + loads[b]
    )
    @constraint(model, breakSym[b=1:(B - 1)], y[b] >= y[b + 1])
    # Objective
    @objective(model, Min, sum(y))
    set_silent(model)
    # Solve
    optimize!(model)
    # Get variables value
    yval = value.(model[:y])
    xval = value.(model[:x])
    # Add new bins if necessary
    for b in length(bins):(B - 1)
        yval[b + 1] == 1 && push!(bins, Bin(fullCapacity))
    end
    # Add commodities to bins
    for i in 1:n, b in 1:B
        xval[i, b] == 1 && add!(bins[b], commodities[i])
    end
    return length(bins) - lengthBefore
end

function milp_packing(bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity})
    newBins = deepcopy(bins)
    milp_packing!(newBins, fullCapacity, commodities)
    return newBins
end
