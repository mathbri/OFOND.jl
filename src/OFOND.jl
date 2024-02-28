module OFOND

# Packages needed across the project

using Graphs
using MetaGraphsNext
using CSV
using JLD2
using IterTools
using Random
using Statistics
using Dates
using Geodesy
using JuMP
using HiGHS

# Project files

include("Constants.jl")
include("Utils.jl")

# Structures 
include("Structures/Network.jl")
include("Structures/TravelTime.jl")
include("Structures/Bin.jl")
include("Structures/TimeSpace.jl")
include("Structures/Commodity.jl")
include("Structures/Order.jl")
include("Structures/Bundle.jl")
include("Structures/Solution.jl")

# Import and Export of data
include("Reading/read_instance.jl")
include("Reading/read_solution.jl")
include("Writing/write_instance.jl")
include("Writing/write_solution.jl")

# Algorithms
include("Algorithms/bin_packing.jl")
# Benchmarks heuristics
include("Algorithms/Benchmark/shortest_delivery.jl")
include("Algorithms/Benchmark/average_delivery.jl")
# Greedy heuristic
include("Algorithms/Greedy/greedy_utils.jl")
include("Algorithms/Greedy/greedy.jl")
# Lower Bound computation and heuristic
include("Algorithms/Lower Bound/semi_linear_bound.jl") 
# Local search heuristic
include("Algorithms/Local Search/bundle_reintroduction.jl")
include("Algorithms/Local Search/two_node_incremental.jl")
include("Algorithms/Local Search/local_search.jl")
# Large Neighborhood Search
include("Algorithms/LNS/lns_utils.jl")
include("Algorithms/LNS/two_node.jl")
include("Algorithms/LNS/attract_reduce.jl")
include("Algorithms/LNS/single_plant.jl")
include("Algorithms/LNS/slope_scaling_mechanism.jl")
include("Algorithms/LNS/lns.jl")

# Functions / Structures to be made public
# With the following export, you can test the different benchmark and heuristic developped (and play with a little) 

export Instance, Solution
export read_instance, read_solution
export shortest_delivery_heuristic, average_delivery_heuristic
export greedy_heuristic
export local_search_heuristic
export semi_linear_bound, semi_linear_bound_heuristic
export lns_heuristic
export write_instance, write_solution

end
