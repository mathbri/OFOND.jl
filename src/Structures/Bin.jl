# Bin structure used in for bin-packing

# TODO : Changing form mutable to immutable could be a way to improve efficiency
mutable struct Bin
    idx::Int                    # index for output purposes
    capacity::Int               # space left in the bin
    content::Vector{Commodity}  # which commodity is in the bin

    Bin(capacity, content) = new(rand(Int), capacity, content)
    Bin(capacity) = new(rand(Int), capacity, Vector{Commodity}())
end

# Methods 

function add!(bin::Bin, commodity::Commodity)
    if bin.capacity >= commodity.size
        push!(bin.content, commodity)
        bin.capacity -= commodity.size
        return true
    end
    return false
end

# Defining zero of a vector of bins / loads for sparse matrices usage

function Base.zero(::Type{Vector{Bin}})
    return Bin[]
end

function Base.zero(::Type{Vector{Int}})
    return Int[]
end
