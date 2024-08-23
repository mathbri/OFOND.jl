# File to be used in Dataiku to launch the computation of network design

using Pkg

# Adding the package from the git repository
Pkg.add(; url="https://github.com/mathbri/OFOND.jl")
# The repository needs to be public to do this

using OFOND

julia_main()
