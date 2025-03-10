# Encapsulating all shared memory used in a struct for ease of usage

struct SharedMemory
    # Channel of capacities used for tentative bin packings 
    capacities::Channel{Vector{Int}}
    # Vector of commodities used for bin packing recompuations
    allCommodities::Vector{Commodity}
    # Vectors and PriorityQueue used for Dijkstra's algorithm
    dists::Vector{Float64}
    parents::Vector{Int}
    queue::PriorityQueue{Int,Float64}
end