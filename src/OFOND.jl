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
using SparseArrays

# Project files

include("Constants.jl")
include("utils.jl")

# Structures 
include("Structures/Network.jl")
include("Structures/Commodity.jl")
include("Structures/Order.jl")
include("Structures/Bundle.jl")
include("Structures/Bin.jl")
include("Structures/TravelTime.jl")
include("Structures/TimeSpace.jl")
include("Structures/projectors.jl")
include("Structures/struct_utils.jl")
include("Structures/Instance.jl")
include("Structures/Solution.jl")

# Import and Export of data
include("ReadingWriting/read_instance.jl")
include("ReadingWriting/read_solution.jl")
include("ReadingWriting/write_solution.jl")

# Algorithms
include("Algorithms/bin_packing.jl")
include("Algorithms/bin_updating.jl")
include("Algorithms/solution_updating.jl")
# Benchmarks heuristics
include("Algorithms/benchmarks.jl")
# Greedy heuristic
include("Algorithms/Utils/greedy_utils.jl")
include("Algorithms/greedy.jl")
# Lower Bound computation and heuristic
include("Algorithms/Utils/lb_utils.jl")
include("Algorithms/lower_bound.jl")
# Local search heuristic
include("Algorithms/Utils/ls_utils.jl")
include("Algorithms/local_search.jl")

include("run.jl")

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
