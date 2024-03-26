# Solution structure

struct Solution
    # Travel time graph (on which paths are computed)
    travelTimeGraph :: TravelTimeGraph
    # Paths used for delivery
    bundlePaths :: Vector{Vector{Int}}
    # Transport units completion through time 
    timeSpaceGraph :: MetaGraph
end

# Methods

function analyze_solution()
    
end

function is_feasible()
    
end

function compute_cost()
    
end