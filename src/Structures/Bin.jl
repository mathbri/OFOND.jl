# Bin structure used in for bin-packing

mutable struct Bin
    availableCapacity :: Int    # space left in the bin
    content :: Dict{UInt, Int}  # which commodity and in which quantity there is in the bin
    
    Bin(availableCapacity, content) = new(availableCapacity, content)
    Bin(availableCapacity) = new(availableCapacity, Dict{UInt, Int}())
end

# Methods 