module OFOND

# Packages needed across the project

using Graphs
using Graphs.LinAlg
using MetaGraphsNext
using CSV
using JLD2 # useful ?
using IterTools
using Random
using Statistics # useful ?
using Dates # useful ?
using Geodesy # useful ?
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
include("Reading/read_instance.jl")
include("Reading/read_solution.jl")
include("Writing/write_instance.jl")
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

# TODO : before handing over the package, create a branch on which :
# - all lns files are deleted
# - docs are done for exported functions
# - unimplemented functions are removed (parrallel stuff on things like that)

# Large Neighborhood Search
include("Algorithms/LNS/lns_utils.jl")
# include("Algorithms/LNS/two_node.jl")
# include("Algorithms/LNS/attract_reduce.jl")
# include("Algorithms/LNS/single_plant.jl")
include("Algorithms/LNS/lns.jl")

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
export lower_bound_heuristic
# export lns_heuristic
export write_instance, write_solution
export julia_main

end
