# Bin structure used in for bin-packing

# TODO : Changing form mutable to immutable could be a way to improve efficiency
mutable struct Bin
    idx::Int                    # index for output purposes
    availableCapacity::Int      # space left in the bin
    content::Vector{Commodity}  # which commodity is in the bin

    Bin(availableCapacity, content) = new(rand(Int), availableCapacity, content)
    Bin(availableCapacity) = new(rand(Int), availableCapacity, Vector{Commodity}())
end

# Methods 

function add!(bin::Bin, commodity::Commodity)
    if bin.availableCapacity >= commodity.size
        push!(bin.content, commodity)
        bin.availableCapacity -= commodity.size
        return true
    end
    return false
end