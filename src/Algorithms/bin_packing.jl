# Bin packing functions

# As expected, this functions remains the bottleneck
# Raises a question : is there a way to avoid garbage collecting and push! operation ?
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
    # TODO : copy what has been done for the tentative first fit operation 
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

# Same function but takes a subArray as argument to work with views of ALL_COMMODITIES
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

# Wrapper for objects
function first_fit_decreasing!(
    bins::Vector{Bin}, arcData::NetworkArc, order::Order; sorted::Bool=false
)
    arcData.capacity <= 0 && println("Arc capacity must be positive $arcData")
    return first_fit_decreasing!(bins, arcData.capacity, order.content; sorted=sorted)
end

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

# Computes the number of bins that would be added if we add the commodities to the bins
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

function tentative_first_fit(
    bins::Vector{Bin},
    fullCapacity::Int,
    commodities::SubArray{
        OFOND.Commodity,1,Vector{OFOND.Commodity},Tuple{UnitRange{Int64}},true
    },
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

# The idea is the following : 
# While searching for the first bin to accomodate the current commodity, we gather information on the current state of the bins
# We can therefore store the biggest capacity encountered throught this search
# If the next commodity is bigger than this capacity, we can start the following search at the previous point of insertion
# This can be extanded easily for the second, third, ... biggest capacities encountered
function findfirstbin2(
    CAPACITIES::Vector{Int}, comSize::Int, sizeCap::Int, startIdx::Int, maxIdx::Int
)
    newCap = sizeCap
    for idxB in startIdx:maxIdx
        # Putting the commodity if we can
        CAPACITIES[idxB] >= comSize && return idxB, newCap
        # Otherwise, updating cap
        newCap = max(newCap, CAPACITIES[idxB])
    end
    # If no bin can fit, returning -1
    return -1, newCap
end

# TODO : test with large instances the equality with classical tentative first fit
# Same process as first fit but storing the second least filled bin encountered to speed up the search
function tentative_first_fit2(
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
    # Setting an overall start idx for the search
    sizeCap, startIdx = 0, 1
    # Adding commodities on top of others
    for idxC in comIdxs
        commodity = commodities[idxC]
        # Checking if the sizeCap allow for loop optimization
        if commodity.size <= sizeCap
            sizeCap, startIdx = 0, 1
        end
        idxB, sizeCap = findfirstbin2(
            CAPACITIES, commodity.size, sizeCap, startIdx, nBinsAft
        )
        if idxB != -1
            CAPACITIES[idxB] -= commodity.size
            startIdx = idxB
        else
            nBinsAft += 1
            add_capacity(CAPACITIES, nBinsAft, fullCapacity - commodity.size)
            startIdx = nBinsAft
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

function tentative_first_fit2(
    bins::Vector{Bin},
    arcData::NetworkArc,
    order::Order,
    CAPACITIES::Vector{Int};
    sorted::Bool=false,
)
    return tentative_first_fit2(
        bins, arcData.capacity, order.content, CAPACITIES; sorted=sorted
    )
end

const BEST_FIT_INF = 1_000_000

# Only useful for best fit decreasing computation of best bin
function best_fit_capacity(bin::Bin, commodity::Commodity)::Int
    capacity_after = bin.capacity - commodity.size
    capacity_after < 0 && return BEST_FIT_INF
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
        bestCapa == BEST_FIT_INF && (push!(bins, Bin(fullCapacity, commodity)); continue)
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
        bestCapa == BEST_FIT_INF && (push!(bins, Bin(fullCapacity, commodity)); continue)
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

# Computes the number of bins that would be added if we add the commodities to the bins
function tentative_best_fit(
    bins::Vector{Bin},
    fullCapacity::Int,
    commodities::SubArray{
        OFOND.Commodity,1,Vector{OFOND.Commodity},Tuple{UnitRange{Int64}},true
    },
    CAPACITIES::Vector{Int};
    sorted::Bool=false,
)
    # As findmin doesn't work on empty bin vectors, making one recursive call here 
    if length(bins) == 0
        return tentative_best_fit(
            [Bin(fullCapacity, commodities[1])],
            fullCapacity,
            view(commodities, 2:length(commodities)),
            CAPACITIES;
            sorted=sorted,
        ) + 1
    end
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
        # Selecting best bin
        bestCapa, bestBin = findmin(
            capa -> commodity.size <= capa ? capa - commodity.size : BEST_FIT_INF,
            CAPACITIES,
        )
        if bestCapa < BEST_FIT_INF
            CAPACITIES[bestBin] -= commodity.size
        else
            nBinsAft += 1
            add_capacity(CAPACITIES, nBinsAft, fullCapacity - commodity.size)
        end
    end
    return nBinsAft - nBinsBef
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

# TODO : adapt Bin, Commodity and read_instance to this addition

# TODO : code simple vector packing functions