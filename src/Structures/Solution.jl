# Solution structure

struct Solution
    # Paths used for delivery (vector of network node hash)
    bundlePaths :: Dict{UInt, Vector{UInt}}
    # Transport units completion through time 
    timeSpaceGraph :: MetaGraph
end

# TODO : add a relaxed solution structure 

# Methods

function analyze_solution()
    
end

function is_feasible()
    
end

function compute_cost()
    
end