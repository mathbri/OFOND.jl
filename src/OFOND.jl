module OFOND

# Packages needed across the project

using Graphs
using Graphs.LinAlg
using MetaGraphsNext
using CSV
using IterTools
using Random
using JuMP
using HiGHS
using SparseArrays
using Flux
using InferOpt

# Project files

include("Constants.jl")
include("Utils.jl")

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
include("Structures/RelaxedSolution.jl")

# Import and Export of data
include("Reading/read_instance.jl")
include("Reading/read_solution.jl")
include("Writing/write_solution.jl")

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
# Large Neighborhood Search
include("Algorithms/LNS/lns_utils.jl")
include("Algorithms/LNS/lns.jl")
# Smart Greedy
include("Algorithms/Smart Greedy/smart_greedy_utils.jl")
include("Algorithms/Smart Greedy/smart_greedy.jl")

include("run.jl")
include("Algorithms/Utils/analysis.jl")

# needed for package compilation
include("julia_main.jl")

# Functions / Structures to be made public
# With the following export, you can test the different benchmark and heuristic developped (and play with a little) 

export Instance, Solution, read_instance, read_solution
export add_properties, tentative_first_fit, extract_sub_instance, extract_sub_solution
export shortest_delivery_heuristic, average_delivery_heuristic
export greedy_heuristic
export local_search_heuristic, greedy_then_ls_heuristic
export lower_bound_heuristic, greedy_or_lb_then_ls_heuristic
export perturbate!, LNS!, slope_scaling_cost_update!, local_search!
# export lns_heuristic
export write_solution
export julia_main, julia_main_test

end
