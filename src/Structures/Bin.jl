# Bin structure used in for bin-packing

# TODO : Changing form mutable to immutable could be a way to improve efficiency

mutable struct Bin
    idx::Int                    # index for output purposes
    capacity::Int               # space left in the bin
    load::Int                   # space used in the bin
    content::Vector{Commodity}  # which commodity is in the bin

    function Bin(capacity::Int, load::Int, content::Vector{Commodity})
        return new(rand(Int), capacity, load, content)
    end
    Bin(capacity::Int) = new(rand(Int), capacity, 0, Vector{Commodity}())
    function Bin(fullCapacity::Int, commodity::Commodity)
        return Bin(fullCapacity - commodity.size, commodity.size, [commodity])
    end
end

# Methods 

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
    bin.load = sum(com -> com.size, bin.content)
    bin.capacity = fullCapa - bin.load
    return contentLength > length(bin.content)
end

function remove!(bin::Bin, commodities::Vector{Commodity})
    removed = false
    for commodity in commodities
        removed = removed || remove!(bin, commodity)
    end
    return removed
end

# TODO
function Base.empty!()
end

# Defining zero of a vector of bins / loads for sparse matrices usage

function Base.zero(::Type{Vector{Bin}})
    return Bin[]
end

function Base.zero(::Type{Vector{Int}})
    return Int[]
end
