# Relaxed Solution structure used for warmstarting milps in LNS

# Change relaxed solution to neighborhood ? an object to store all neede information for solving the neighborhood ?

struct RelaxedSolution
    # Paths used for delivery
    bundleIdxs::Vector{Int}
    bundlePaths::Vector{Vector{Int}}
    # Transport units completion through time 
    loads::SparseMatrixCSC{Int,Int}
end

# TODO : there may be a need to create this more efficiently, to test
function RelaxedSolution(solution::Solution, instance::Instance, bundles::Vector{Bundle})
    I, J, V = Int[], Int[], Int[]
    for (src, dst) in instance.timeSpaceGraph.commonArcs
        push!(I, src)
        push!(J, dst)
        push!(V, sum(bin.load for bin in solution.bins[src, dst]; init=0))
    end
    bunIdxs = idx(bundles)
    return RelaxedSolution(bunIdxs, solution.bundlePaths[bunIdxs], sparse(I, J, V))
end