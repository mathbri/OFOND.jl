# File to be used in Dataiku to launch the computation of network design

using Pkg

println("Removing current OFOND version")
Pkg.rm("OFOND")

# Adding the package from the git repository
println("Installing V0-dataiku version of OFOND")
Pkg.add(; url="https://github.com/mathbri/OFOND.jl", rev="V0-dataiku")
# The repository needs to be public to do this

using OFOND

julia_main()
