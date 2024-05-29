# Bin structure used in for bin-packing

# TODO : Changing form mutable to immutable could be a way to improve efficiency

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
        return Bin(fullCapacity - size(commodity), size(commodity), [commodity])
    end
end

# Methods 

function Base.:(==)(bin1::Bin, bin2::Bin)
    return bin1.capacity == bin2.capacity &&
           bin1.load == bin2.load &&
           bin1.content == bin2.content
end

function add!(bin::Bin, commodity::Commodity)
    if bin.capacity >= size(commodity)
        push!(bin.content, commodity)
        bin.capacity -= size(commodity)
        bin.load += size(commodity)
        return true
    end
    return false
end

function remove!(bin::Bin, commodity::Commodity)
    fullCapa, contentLength = bin.capacity + bin.load, length(bin.content)
    filter!(com -> com != commodity, bin.content)
    bin.load = sum(com -> size(com), bin.content; init=0)
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

function get_all_commodities(bins::Vector{Bin})
    return reduce(vcat, map(bin -> bin.content, bins); init=Commodity[])
end

# Defining zero of a vector of bins / loads for sparse matrices usage

function Base.zero(::Type{Vector{Bin}})
    return Bin[]
end
