# File to be used in Dataiku to launch the computation of network design

using Pkg

println("Removing current OFOND version")
Pkg.rm("OFOND")

# Adding the package from the git repository
println("Installing V0-dataiku version of OFOND")
Pkg.add(; url="https://github.com/mathbri/OFOND.jl", rev="V1-dataiku")
# The repository needs to be public to do this

using OFOND
using JSON

# Reading parameter file 
println("Launching OFO Network Design")
println("Arguments : ", ARGS)
parameters = JSON.parsefile(ARGS[1])

# Launching optimization
julia_main(;
    inputFolder=parameters["input"],
    outputFolder=parameters["output"],
    useILS=parameters["model"] == "LNS",
    useWeights=parameters["weight"],
)
