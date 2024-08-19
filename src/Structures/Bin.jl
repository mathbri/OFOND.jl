# Bin structure used in for bin-packing

# TODO : Changing form mutable to immutable could be a way to improve efficiency

# TODO : If you store sizes and costs in separate common vectors, the bin content could be a vector of indexes or a sparse vector storing (idx,quantity) 

mutable struct Bin
    idx::Int                    # index for output purposes
    capacity::Int               # space left in the bin
    load::Int                   # space used in the bin
    content::Vector{Commodity}  # which commodity is in the bin

    function Bin(capacity::Int, load::Int, content::Vector{Commodity})
        @assert capacity >= 0 && load >= 0
        return new(rand(Int), capacity, load, content)
    end
    Bin(capacity::Int) = new(rand(Int), capacity, 0, Vector{Commodity}())
    function Bin(fullCapacity::Int, commodity::Commodity)
        commodity.size > fullCapacity && return Bin(0, fullCapacity, [commodity])
        return Bin(fullCapacity - commodity.size, commodity.size, [commodity])
    end
end

# Methods 

function Base.:(==)(bin1::Bin, bin2::Bin)
    return bin1.capacity == bin2.capacity &&
           bin1.load == bin2.load &&
           bin1.content == bin2.content
end

function Base.show(io::IO, bin::Bin)
    return print(io, "Bin($(bin.capacity), $(bin.load), $(bin.content))")
end

function add!(bin::Bin, commodity::Commodity)
    if bin.capacity >= commodity.size
        push!(bin.content, commodity)
        bin.capacity -= commodity.size
        bin.load += commodity.size
        return true
    end
    return false
end

function remove!(bin::Bin, commodity::Commodity)
    fullCapa, contentLength = bin.capacity + bin.load, length(bin.content)
    filter!(com -> com != commodity, bin.content)
    bin.load = sum(com -> com.size, bin.content; init=0)
    bin.capacity = fullCapa - bin.load
    return contentLength > length(bin.content)
end

function remove!(bin::Bin, commodities::Vector{Commodity})
    hasRemoved = false
    for commodity in commodities
        removed = remove!(bin, commodity)
        hasRemoved = hasRemoved || removed
    end
    return hasRemoved
end

# TODO : same remark as capacities (but less important in profiling)
# Vector to be used when calling the get all commodities function
# Used mainly for garbage collection avoidance 
global ALL_COMMODITIES = Commodity[]

function get_all_commodities(bins::Vector{Bin})
    # verify the global vector is long enough 
    nCom = sum(length(bin.content) for bin in bins; init=0)
    if nCom > length(ALL_COMMODITIES)
        append!(ALL_COMMODITIES, fill(bins[1].content[1], nCom - length(ALL_COMMODITIES)))
    end
    # put all commodities in the global vector
    idx = 1
    for bin in bins
        for com in bin.content
            ALL_COMMODITIES[idx] = com
            idx += 1
        end
    end
    return view(ALL_COMMODITIES, 1:nCom)
end

function stock_cost(bin::Bin)
    return sum(com.stockCost for com in bin.content; init=0.0)
end

# Defining zero of a vector of bins / loads for sparse matrices usage

function Base.zero(::Type{Vector{Bin}})
    return Bin[]
end
