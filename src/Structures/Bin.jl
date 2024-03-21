# Bin structure used in for bin-packing

mutable struct Bin
    idx :: Int                    # index for output purposes
    availableCapacity :: Int      # space left in the bin
    content :: Vector{Commodity}  # which commodity is in the bin
    
    Bin(availableCapacity, content) = new(availableCapacity, content)
    Bin(availableCapacity) = new(availableCapacity, Vector{Commodity}())
end

# Methods 