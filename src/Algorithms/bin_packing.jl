# Bin packing functions

# TODO : FFD and BFD have faster implementations using binary trees 
# Need to see if bin packing remains a bottleneck by number of problems to solve or time per problem
# see Faster First Fit for algorithm
# see AVL Tree in DataStructures.jl for implementation
# see sorted containers and serach_sorted_first function for Fatser BFD
# maybe those implementations are not suited for this purpose and there is a need for a custom tree implem (or search)
# ex : a new struture with one field being actual bins and the other being the tree used for search 

# TODO : add other bin packing computations to improve this neighborhood

# TODO :check if it is a good idea (probably not for now, need some more work)
# To remove the push operation, good idea to create a 4d tensor of booleans indicating true if commodity c is in bin b of arc i-j ?
# Really sparse matrix but could be optimized with BitArray
# One matrix per arc ?
# Thats for the content and we have a matrix (or vertor per arc) for capacities and same for loads

# TODO : find a way to define one function for arrays and subarrays

# TODO : as expected, this functions remains the bottleneck, is there a way to avoid garbage collecting and push! operation ?
function first_fit_decreasing!(
    bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity}; sorted::Bool=false
)
    # Sorting commodities in decreasing order of size (if not already done)
    comIdxs = if !sorted
        sortperm(commodities; rev=true)
    else
        eachindex(commodities)
    end
    lengthBefore = length(bins)
    # Adding commodities on top of others
    for idxC in comIdxs
        commodity = commodities[idxC]
        # TODO : maybe it would be faster to computes with CAPACITIES to find the index in which to put the commodity and then put it 
        idxB = findfirst(bin -> add!(bin, commodity), bins)
        # TODO : this push! operation is taking most of the time in different profiling, probably because of garbage collecting and reallocation
        # pre-allocate empty bins ? maybe not a good idea
        idxB === nothing && push!(bins, Bin(fullCapacity, commodity))
    end
    return length(bins) - lengthBefore
end

# Specialized version for the subarrays
function first_fit_decreasing!(
    bins::Vector{Bin},
    fullCapacity::Int,
    commodities::SubArray{
        OFOND.Commodity,1,Vector{OFOND.Commodity},Tuple{UnitRange{Int64}},true
    };
    sorted::Bool=false,
)
    # Sorting commodities in decreasing order of size (if not already done)
    comIdxs = if !sorted
        sortperm(commodities; rev=true)
    else
        eachindex(commodities)
    end
    lengthBefore = length(bins)
    # Adding commodities on top of others
    for idxC in comIdxs
        commodity = commodities[idxC]
        idxB = findfirst(bin -> add!(bin, commodity), bins)
        idxB === nothing && push!(bins, Bin(fullCapacity, commodity))
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

function first_fit_decreasing(
    bins::Vector{Bin},
    fullCapacity::Int,
    commodities::SubArray{
        OFOND.Commodity,1,Vector{OFOND.Commodity},Tuple{UnitRange{Int64}},true
    };
    sorted::Bool=false,
)
    newBins = deepcopy(bins)
    first_fit_decreasing!(newBins, fullCapacity, commodities; sorted=sorted)
    return newBins
end

# Wrapper for objects
function first_fit_decreasing!(
    bins::Vector{Bin}, arcData::NetworkArc, order::Order; sorted::Bool=false
)
    arcData.capacity <= 0 && println("Arc capacity must be positive $arcData")
    return first_fit_decreasing!(bins, arcData.capacity, order.content; sorted=sorted)
end

# TODO : pre allocate a vector is a good idea but for it to be efficient in julia it must be passed as an argument in functions and not in the global scope

function get_capacities(bins::Vector{Bin}, CAPACITIES::Vector{Int})
    # if the vector of bins is larger than the current cpapcity vector, growing it
    if length(bins) > length(CAPACITIES)
        append!(CAPACITIES, fill(0, length(bins) - length(CAPACITIES)))
    end
    # updating values in capcities vector
    for (idx, bin) in enumerate(bins)
        CAPACITIES[idx] = bin.capacity
    end
    # filling with -1 for not opened bins
    CAPACITIES[(length(bins) + 1):end] .= -1
    return length(bins), length(bins)
end

function add_capacity(CAPACITIES::Vector{Int}, idx::Int, capacity::Int)
    if idx > length(CAPACITIES)
        push!(CAPACITIES, capacity)
    else
        CAPACITIES[idx] = capacity
    end
end

function findfirstbin(CAPACITIES::Vector{Int}, comSize::Int, maxIdx::Int)
    for (i, capa) in enumerate(CAPACITIES)
        i > maxIdx && return -1
        capa >= comSize && return i
    end
    return -1
end

# TODO : transform CAPACITIES into a tree to speed up the search ? AVLTree with keys (capa, binIndex)
# TODO : define my own findfirst to always return an Int ?
# findfirst on view may be more inefficient than findfirst on the original array and length
function tentative_first_fit(
    bins::Vector{Bin},
    fullCapacity::Int,
    commodities::Vector{Commodity},
    CAPACITIES::Vector{Int};
    sorted::Bool=false,
)
    # Sorting commodities in decreasing order of size (if not already done)
    comIdxs = if !sorted
        sortperm(commodities; rev=true)
    else
        eachindex(commodities)
    end
    nBinsBef, nBinsAft = get_capacities(bins, CAPACITIES)
    # Adding commodities on top of others
    for idxC in comIdxs
        commodity = commodities[idxC]
        idxB = findfirstbin(CAPACITIES, commodity.size, nBinsAft)
        # idxB = findfirst(cap -> cap >= commodity.size, CAPACITIES[1:nBinsAft])
        if idxB != -1
            CAPACITIES[idxB] -= commodity.size
        else
            nBinsAft += 1
            add_capacity(CAPACITIES, nBinsAft, fullCapacity - commodity.size)
        end
    end
    return nBinsAft - nBinsBef
end

# Wrapper for objects
function tentative_first_fit(
    bins::Vector{Bin},
    arcData::NetworkArc,
    order::Order,
    CAPACITIES::Vector{Int};
    sorted::Bool=false,
)
    return tentative_first_fit(
        bins, arcData.capacity, order.content, CAPACITIES; sorted=sorted
    )
end

# Only useful for best fit decreasing computation of best bin
function best_fit_capacity(bin::Bin, commodity::Commodity)
    capacity_after = bin.capacity - commodity.size
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

function best_fit_decreasing!(
    bins::Vector{Bin},
    fullCapacity::Int,
    commodities::SubArray{
        OFOND.Commodity,1,Vector{OFOND.Commodity},Tuple{UnitRange{Int64}},true
    };
    sorted::Bool=false,
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

function best_fit_decreasing(
    bins::Vector{Bin},
    fullCapacity::Int,
    commodities::SubArray{
        OFOND.Commodity,1,Vector{OFOND.Commodity},Tuple{UnitRange{Int64}},true
    };
    sorted::Bool=false,
)
    newBins = deepcopy(bins)
    best_fit_decreasing!(newBins, fullCapacity, commodities; sorted=sorted)
    return newBins
end

# TODO : check whether the MOI BinPacking constraint is more efficient for solving 

# Milp model for adding commodities on top
function milp_packing!(bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity})
    n = length(commodities)
    n == 0 && return nothing
    lengthBefore = length(bins)
    CAPACITIES = Int[bin.capacity for bin in bins]
    B = lengthBefore + tentative_first_fit(bins, fullCapacity, commodities, CAPACITIES)
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
        fullCapacity * y[b] >= sum(x[i, b] * commodities[i].size for i in 1:n) + loads[b]
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

function milp_packing(
    bins::Vector{Bin},
    fullCapacity::Int,
    commodities::SubArray{
        OFOND.Commodity,1,Vector{OFOND.Commodity},Tuple{UnitRange{Int64}},true
    },
)
    n = length(commodities)
    n == 0 && return nothing
    lengthBefore = length(bins)
    B =
        lengthBefore +
        length(first_fit_decreasing(bins, fullCapacity, commodities; sorted=true))
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
        fullCapacity * y[b] >= sum(x[i, b] * commodities[i].size for i in 1:n) + loads[b]
    )
    @constraint(model, breakSym[b=1:(B - 1)], y[b] >= y[b + 1])
    # Objective
    @objective(model, Min, sum(y))
    set_silent(model)
    # Solve
    optimize!(model)
    return round(Int, objective_value(model))
end

function milp_packing(bins::Vector{Bin}, fullCapacity::Int, commodities::Vector{Commodity})
    newBins = deepcopy(bins)
    milp_packing!(newBins, fullCapacity, commodities)
    return newBins
end

###########################################################################################
# Vector packing functions
###########################################################################################

# TODO : code simple vector packing functions