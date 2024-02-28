module OFOND

# Packages needed across the project

using Graphs, MetaGraphsNext
using CSV, JLD2
using IterTools
using Random, Statistics
using Dates
using Geodesy
using JuMP, Gurobi, HiGHS

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
include("Reading/load_instance.jl")
include("Reading/load_solution.jl")
include("Writing/write_instance.jl")
include("Writing/write_solution.jl")

# Algorithms
include("Algorithms/bin_packing.jl")
# Benchmarks heuristics
include("Algorithms/Benchmark/shortest_delivery.jl")
include("Algorithms/Benchmark/average_delivery.jl")
# Greedy heuristic
include("Algorithms/Greedy/greedy_utils.jl")
include("Algorithms/Greedy/greedy_heuristic.jl")
# Lower Bound computation and heuristic
include("Algorithms/Lower Bound/semi_linear_bound.jl") 
# Local search heuristic
include("Algorithms/Local Search/bundle_reintroduction.jl")
include("Algorithms/Local Search/two_node_incremental.jl")
# Large Neighborhood Search
include("Algorithms/LNS/lns_utils.jl")
include("Algorithms/LNS/two_node_perturbation.jl")
include("Algorithms/LNS/attract_reduce_perturbation.jl")
include("Algorithms/LNS/single_plant_perturbation.jl")
include("Algorithms/LNS/slope_scaling_mechanism.jl")

# Functions / Structures to be made public

end
