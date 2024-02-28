module OFOND

# Packages needed across the project

using Graphs, MetaGraphsNext

# Project files

include("Constants.jl")
include("Utils.jl")

# Structures 
include("Structures/Network.jl")
include("Structures/TravelTime.jl")
include("Structures/Bin.jl")
include("Structures/TimeSpace.jl")

# Import and Export of data

# Algorithms

# then export the functions / structures to be made public

end
