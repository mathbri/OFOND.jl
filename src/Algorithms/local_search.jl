# Local search heuristic and building blocks

# For the minimal flow on maritime arcs, one solution is to check at removal time if the quantities left satisfy the minimal flow, if not just recomuting path to and from oversea arc 
# At insertion time, if the added flow don't make enough for the constraint, arc is forbidden (INF) cost
# Another option for insertion is to make a first round of insertion without constraint and if there is arcs that does not satisfy, 
#    - take all bundles of it, forbid arc for every one and recompute insertion and repaeat until constraint are good

# When we will split bundles, a new neighborhhod based on the perturb than optimize is to a full path for the old bundle and then reintroduce with the new bundles
# It can also be done between two nodes of the shared network 

# TODO : add a milp packing improvement for direct and non-linear outsource arcs in a final packing option 

# Improving all bin packings if possible
# The idea is to put skip linear to false just before returning the solution to get a more compact solution but it does not affect the cost
function bin_packing_improvement!(
    solution::Solution,
    instance::Instance,
    ALL_COMMODITIES::Vector{Commodity},
    CAPACITIES::Vector{Int};
    sorted::Bool=false,
    skipLinear::Bool=true,
)
    # @assert is_feasible(instance, solution; verbose=true)
    costImprov, computedNoImprov, computable, candidate = 0.0, 0, 0, 0
    # Efficient iteration over sparse matrices
    rows = rowvals(solution.bins)
    vals = nonzeros(solution.bins)
    for j in 1:size(solution.bins, 2)
        for idx in nzrange(solution.bins, j)
            i = rows[idx]
            arcBins = solution.bins[i, j]
            arcData = instance.timeSpaceGraph.networkArcs[i, j]
            length(arcBins) > 1 && (computable += 1)
            # If no improvement possible
            is_bin_candidate(arcBins, arcData; skipLinear=skipLinear) || continue
            candidate += 1
            # Gathering all commodities
            allCommodities = get_all_commodities(arcBins, ALL_COMMODITIES)
            # Computing tentative new bins
            ffdBins = tentative_first_fit(arcData, allCommodities, CAPACITIES)
            bfdBins = tentative_best_fit(arcData, allCommodities, CAPACITIES)
            # If the number of bins did not change, skipping next
            lengthBefore = length(arcBins)
            if min(ffdBins, bfdBins) >= lengthBefore
                computedNoImprov += 1
                continue
            end
            # Computing new bins
            empty!(arcBins)
            capaV = arcData.capacity
            if ffdBins < bfdBins
                first_fit_decreasing!(arcBins, capaV, allCommodities)
            else
                best_fit_decreasing!(arcBins, capaV, allCommodities)
            end
            # Computing cost improvement (unless linear arc)
            arcData.isLinear && continue
            costImprov -= arcData.unitCost * (lengthBefore - min(ffdBins, bfdBins))
        end
    end
    println("All packings computable : $computable")
    println("Computed packings (lower bound not reached) : $candidate")
    println("Computed packings with no improvement : $computedNoImprov")
    # @assert is_feasible(instance, solution; verbose=true)
    return costImprov
end

# Parallel version of the bin packing improvement
function parallel_bin_packing_improvement!(
    solution::Solution, instance::Instance; sorted::Bool=false, skipLinear::Bool=true
)
    # @assert is_feasible(instance, solution; verbose=true)
    # Creating channels to limit memory footprint
    chnlCom = Channel{Vector{Commodity}}(Threads.nthreads())
    foreach(1:Threads.nthreads()) do _
        put!(chnlCom, Vector{Commodity}(undef, 0))
    end
    chnlCapa = Channel{Vector{Int}}(Threads.nthreads())
    foreach(1:Threads.nthreads()) do _
        put!(chnlCapa, Vector{Int}(undef, 0))
    end
    # Filtering things to compute
    computables = Tuple{Int,Int}[]
    rows = rowvals(solution.bins)
    vals = nonzeros(solution.bins)
    for j in 1:size(solution.bins, 2)
        for idx in nzrange(solution.bins, j)
            i = rows[idx]
            arcData = instance.timeSpaceGraph.networkArcs[i, j]
            arcBins = solution.bins[i, j]
            if is_bin_candidate(arcBins, arcData; skipLinear=skipLinear)
                push!(computables, (i, j))
            end
        end
    end
    println("All packings computable : $(length(computables))")
    # Parallelizing actual computations
    counts = tmapreduce(.+, computables) do (aSrc, aDst)
        arcBins = solution.bins[aSrc, aDst]
        arcData = instance.timeSpaceGraph.networkArcs[aSrc, aDst]
        ALL_COMMODITIES = take!(chnlCom)
        CAPACITIES = take!(chnlCapa)
        # Gathering all commodities
        allCommodities = get_all_commodities(arcBins, ALL_COMMODITIES)
        # Computing tentative new bins
        ffdBins = tentative_first_fit(arcData, allCommodities, CAPACITIES)
        bfdBins = tentative_best_fit(arcData, allCommodities, CAPACITIES)
        # If the number of bins did not change, skipping next
        lengthBefore = length(arcBins)
        if min(ffdBins, bfdBins) >= length(arcBins)
            # Returning that the bin was computable but no improvement found
            0.0, 1, true, 1
        else
            # Computing new bins
            empty!(arcBins)
            capaV = arcData.capacity
            if ffdBins < bfdBins
                first_fit_decreasing!(arcBins, capaV, allCommodities; sorted=true)
            else
                best_fit_decreasing!(arcBins, capaV, allCommodities; sorted=true)
            end
            # Computing cost improvement (unless linear arc)
            if arcData.isLinear
                0.0, 0, true, 1
            else
                -arcData.unitCost * (lengthBefore - min(ffdBins, bfdBins)), 0, true, 1
            end
        end
    end
    costImprov, computedNoImprov, computable, candidate = counts
    println("Computed packings (lower bound not reached) : $candidate")
    println("Computed packings with no improvement : $computedNoImprov")
    # @assert is_feasible(instance, solution; verbose=true)
    return costImprov
end

function revert_solution!(
    solution::Solution,
    instance::Instance,
    bundles::Vector{Bundle},
    oldPaths::Vector{Vector{Int}},
    oldBins::SparseMatrixCSC{Vector{Bin},Int},
    newPaths::Vector{Vector{Int}}=[Int[]],
)
    if length(newPaths[1]) > 0
        update_solution!(solution, instance, bundles, newPaths; remove=true)
    end
    update_solution!(solution, instance, bundles, oldPaths; skipRefill=true)
    return revert_bins!(solution, oldBins)
end

function revert_solution!(solution::Solution, instance::Instance, prevSol::Solution)
    newPaths = deepcopy(solution.bundlePaths)
    return revert_solution!(
        solution, instance, instance.bundles, prevSol.bundlePaths, prevSol.bins, newPaths
    )
end

function revert_solution!(
    solution::Solution,
    instance::Instance,
    bundle::Bundle,
    oldPath::Vector{Int},
    oldBins::SparseMatrixCSC{Vector{Bin},Int},
    newPath::Vector{Int}=Int[],
)
    if length(newPath) > 0
        update_solution!(solution, instance, bundle, newPath; remove=true)
    end
    update_solution!(solution, instance, bundle, oldPath; skipRefill=true)
    return revert_bins!(solution, oldBins)
end

function debug_reinsertion(
    instance::Instance,
    solution::Solution,
    bundle::Bundle,
    shortestPath::Vector{Int},
    CHANNEL::Channel{Vector{Int}},
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Reverting solution 
    revert_solution!(solution, instance, bundle, oldPath, oldBins)
    # Re-doing the bundle removal, cost computation and updating 
    file = open("debug.txt", "w")
    redirect_stdout(file)
    costRemoved = update_solution!(
        solution, instance, bundle, oldPath; remove=true, verbose=true
    )
    println("#############################################################")
    println("\n\nFull cost removed : $costRemoved\n\n")
    println("#############################################################")

    # Inserting it back
    suppNode = TTGraph.bundleSrc[bundle.idx]
    custNode = TTGraph.bundleDst[bundle.idx]
    newPath, pathCost = greedy_insertion2(
        solution, TTGraph, TSGraph, bundle, suppNode, custNode, CHANNEL; verbose=true
    )
    println("#############################################################")
    println("\n\nNew path : $newPath with cost $pathCost\n\n")
    println("#############################################################")

    fullTentativeCost = 0.0
    for (aSrc, aDst) in partition(newPath, 2, 1)
        println(
            "\nIs update candidate : $(is_update_candidate(TTGraph, aSrc, aDst, bundle))"
        )
        println("Computing tenetaive cost for arc $aSrc -> $aDst")
        arcUpdateCost = arc_update_cost(
            solution, TTGraph, TSGraph, bundle, aSrc, aDst, Int[]; sorted=true, verbose=true
        )
        fullTentativeCost += arcUpdateCost
        println("\nComputed cost for arc $aSrc -> $aDst : $arcUpdateCost")
        println("Reference cost for arc $aSrc -> $aDst : $(TTGraph.costMatrix[aSrc, aDst])")

        actualUpdateCost = update_arc_bins!(
            solution2, TSGraph, TTGraph, bundle, aSrc, aDst; verbose=true
        )
        fullActualCost += actualUpdateCost
        println("\nActual Computed cost for arc $aSrc -> $aDst : $actualUpdateCost")
    end

    println("#############################################################")
    println("\n\n Full recomputed path cost : $fullTentativeCost \n\n")
    println("#############################################################")

    updateCost = update_solution!(
        solution, instance, bundle, newPath; sorted=true, verbose=true
    )

    println("#############################################################")
    println("\n\nFull Update cost : $updateCost\n\n")
    println("#############################################################")

    close(file)
    # Throwing error
    throw("Computed path cost and update cost don't match")
end

# TODO : profile again because it seems too slow for what it has done in the past
# Removing and inserting back the bundle in the solution.
# If the operation did not lead to a cost improvement, reverting back to the former state of the solution.
function bundle_reintroduction!(
    solution::Solution,
    instance::Instance,
    bundle::Bundle,
    CAPACITIES::Vector{Int};
    sorted::Bool=false,
    current_cost::Bool=false,
    costThreshold::Float64=EPS,
    directReIntro::Bool=false,
)::Float64
    # @assert is_feasible(instance, solution; verbose=true)
    # println()
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    oldPath = solution.bundlePaths[bundle.idx]
    # The filtering could also occur in terms of cost removed : it must be above a certain threshold
    estimRemCost = bundle_estimated_removal_cost(bundle, oldPath, instance, solution)
    if estimRemCost <= costThreshold
        # println(
        #     "Estimated removal cost ($estimRemCost) inferior to the threshold ($costThreshold), aborting",
        # )
        return 0.0
    end

    # println("Estimated removal cost = $estimRemCost")
    # println("Reinserting bundle $bundle")

    # Saving previous bins and removing bundle
    oldBins = save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, [bundle], [oldPath])
    )
    costRemoved = update_solution!(solution, instance, bundle, oldPath; remove=true)
    # println("Cost removed = $costRemoved")

    # Inserting it back
    suppNode = TTGraph.bundleSrc[bundle.idx]
    custNode = TTGraph.bundleDst[bundle.idx]
    newPath, pathCost = greedy_insertion(
        solution,
        TTGraph,
        TSGraph,
        bundle,
        suppNode,
        custNode,
        CAPACITIES;
        sorted=sorted,
        current_cost=current_cost,
    )
    # println("New path = $newPath")
    # println("Cost added = $pathCost")

    # Updating path if it improves the cost (accounting for EPS cost on arcs)
    if pathCost + costRemoved < -1e-3 || directReIntro
        # println("Updating path\n")
        # Adding to solution
        update_solution!(solution, instance, bundle, newPath; sorted=sorted)
        # @assert is_feasible(instance, solution; verbose=true)
        return pathCost + costRemoved
    else
        # println("Reverting solution\n")
        revert_solution!(solution, instance, bundle, oldPath, oldBins)
        # @assert is_feasible(instance, solution; verbose=true)
        return 0.0
    end
end

function bundle_reintroduction2!(
    solution::Solution,
    instance::Instance,
    bundle::Bundle,
    CHANNEL::Channel{Vector{Int}};
    costThreshold::Float64=EPS,
    directReIntro::Bool=false,
)::Float64
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    oldPath = solution.bundlePaths[bundle.idx]
    # The filtering could also occur in terms of cost removed : it must be above a certain threshold
    estimRemCost = bundle_estimated_removal_cost(bundle, oldPath, instance, solution)
    if estimRemCost <= costThreshold
        return 0.0
    end

    # TODO : most of the local search time lost in saving previous bins, getting bins updated and dijkstra computing 
    # Here we can have also a shared memory for a "tentative solution" with only capacities stored and not the actual bins
    # The removal and insertion can then happen only when there is improvement 
    # There is also no need to allocate the revious bins matrix
    # It can be in the form of a second sparse matrix in the solution object only storing Vectors of Ints and a tentative_update_solution to "remove" the bundle from this solution

    # Saving previous bins and removing bundle
    oldBins = save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, [bundle], [oldPath])
    )
    costRemoved = update_solution!(solution, instance, bundle, oldPath; remove=true)
    # Inserting it back
    suppNode = TTGraph.bundleSrc[bundle.idx]
    custNode = TTGraph.bundleDst[bundle.idx]
    newPath, pathCost = greedy_insertion2(
        solution, TTGraph, TSGraph, bundle, suppNode, custNode, CHANNEL
    )
    # Updating path if it improves the cost (accounting for EPS cost on arcs)
    if pathCost + costRemoved < -1e-3 || directReIntro
        # Adding to solution
        updateCost = update_solution!(solution, instance, bundle, newPath; sorted=true)
        if !isapprox(updateCost, pathCost; atol=1.0)
            debug_reinsertion(instance, solution, bundle, newPath, CHANNEL)
        end
        return pathCost + costRemoved
    else
        revert_solution!(solution, instance, bundle, oldPath, oldBins)
        return 0.0
    end
end

function reintroduce_bundles!(
    solution::Solution,
    instance::Instance,
    bundleIdxs::Vector{Int};
    costThreshold::Float64=EPS,
    timeLimit::Int=60,
    directReIntro::Bool=false,
)
    timeLimit > 0 || return nothing
    count, start, totImpro = 0, time(), 0.0
    CHANNEL = create_filled_channel()
    print("Bundle reintroduction progress : ")
    percentIdx = ceil(Int, length(bundleIdxs) / 100)
    for (i, bundleIdx) in enumerate(bundleIdxs)
        bundle = instance.bundles[bundleIdx]
        improvement = bundle_reintroduction2!(
            solution,
            instance,
            bundle,
            CHANNEL;
            costThreshold=costThreshold,
            directReIntro=directReIntro,
        )
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i * 100 / length(bundleIdxs)))% ")
        totImpro += improvement
        improvement < -1e-3 && (count += 1)
        time() - start > timeLimit && break
    end
    println()
    feasible = is_feasible(instance, solution)
    timeTaken = round(time() - start; digits=1)
    totImpro = round(totImpro; digits=1)
    @info "Total bundle re-introduction improvement" :bundles_updated = count :improvement =
        totImpro :time = timeTaken :feasible = feasible
    return totImpro
end

# Remove and insert back all bundles flowing from src to dst 
function two_node_incremental!(
    solution::Solution,
    instance::Instance,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int};
    sorted::Bool=false,
    current_cost::Bool=false,
    costThreshold::Float64=EPS,
)
    @assert is_feasible(instance, solution; verbose=true)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    twoNodeBundleIdxs = get_bundles_to_update(TTGraph, solution, src, dst)
    twoNodeBundles = instance.bundles[twoNodeBundleIdxs]
    # If there is no bundles concerned, returning
    length(twoNodeBundles) == 0 && return 0.0, 0
    # println("\nUpdating bundles $twoNodeBundleIdxs between nodes $src and $dst")
    oldPaths = get_paths_to_update(solution, twoNodeBundles, src, dst)
    # println("Old paths : $oldPaths")

    # The filtering could also occur in terms of cost removed : it must be above a certain threshold
    estimRemCost = sum(
        bundle_estimated_removal_cost(bundle, path, instance, solution) for
        (bundle, path) in zip(twoNodeBundles, oldPaths)
    )
    # println("Estimated removal cost = $estimRemCost")
    estimRemCost <= costThreshold && return 0.0, 0

    # Saving previous bins and removing bundle 
    oldBins = save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, twoNodeBundles, oldPaths)
    )
    costRemoved = update_solution!(
        solution, instance, twoNodeBundles, oldPaths; remove=true
    )
    # println("Cost removed = $costRemoved")

    # Inserting it back
    addedCost = 0.0
    # sortedBundleIdxs = sortperm(twoNodeBundles; by=bun -> bun.maxPackSize, rev=true)
    sortedBundleIdxs = randperm(length(twoNodeBundles))
    newPaths = [Int[] for _ in 1:length(twoNodeBundles)]
    for bundleIdx in sortedBundleIdxs
        bundle = twoNodeBundles[bundleIdx]
        newPath, pathCost = greedy_insertion(
            solution,
            TTGraph,
            TSGraph,
            bundle,
            src,
            dst,
            CAPACITIES;
            sorted=sorted,
            current_cost=current_cost,
        )
        # Adding to solutions
        addedCost += update_solution!(solution, instance, bundle, newPath; sorted=sorted)
        newPaths[bundleIdx] = newPath
    end
    # println("New paths : $newPaths")
    # println("Cost added = $addedCost")

    # Solution already updated so if it didn't improve, reverting to old state
    if addedCost + costRemoved > -1e-3
        # println("Reverting solution\n")
        revert_solution!(solution, instance, twoNodeBundles, oldPaths, oldBins, newPaths)
        @assert is_feasible(instance, solution; verbose=true)
        return 0.0, 0
    else
        # println("Keeping new paths\n")
        @assert is_feasible(instance, solution; verbose=true)
        return addedCost + costRemoved, length(twoNodeBundles)
    end
end

# Remove and insert back all bundles flowing from src to dst on the same path
function two_node_common!(
    solution::Solution,
    instance::Instance,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int};
    costThreshold::Float64=EPS,
)
    @assert is_feasible(instance, solution; verbose=true)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    twoNodeBundleIdxs = get_bundles_to_update(TTGraph, solution, src, dst)
    twoNodeBundles = instance.bundles[twoNodeBundleIdxs]
    # If there is no bundles concerned, returning
    length(twoNodeBundles) == 0 && return 0.0, 0
    # println("\nUpdating bundles $twoNodeBundleIdxs between nodes $src and $dst")
    oldPaths = get_paths_to_update(solution, twoNodeBundles, src, dst)

    # The filtering could also occur in terms of cost removed : it must be above a certain threshold
    estimRemCost = sum(
        bundle_estimated_removal_cost(bundle, path, instance, solution) for
        (bundle, path) in zip(twoNodeBundles, oldPaths)
    )
    # println("Estimated removal cost = $estimRemCost")
    estimRemCost <= costThreshold && return 0.0, 0

    # Saving previous bins and removing bundle 
    oldBins = save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, twoNodeBundles, oldPaths)
    )
    costRemoved = update_solution!(
        solution, instance, twoNodeBundles, oldPaths; remove=true
    )
    # println("Cost removed = $costRemoved")

    # Creating a unique bundle for all the bundles concerned
    commonBundle = fuse_bundles(instance, twoNodeBundles, CAPACITIES)
    # Inserting it back
    newPath, addedCost = greedy_insertion(
        solution,
        TTGraph,
        TSGraph,
        commonBundle,
        src,
        dst,
        CAPACITIES;
        sorted=true,
        findSources=false,
    )
    # println("New path : $newPath")
    # println("Cost added = $addedCost")

    # Checking feasibility in terms of elementarity remains a question here
    feasible = true
    # Updating path possible if it improves the cost and the new paths are admissible
    if (addedCost + costRemoved < -1e-3) && feasible
        # println("Keeping new path\n")
        newPaths = [newPath for _ in 1:length(twoNodeBundles)]
        updateCost = update_solution!(
            solution, instance, twoNodeBundles, newPaths; sorted=true
        )
        print("o")
        @assert is_feasible(instance, solution; verbose=true)
        return updateCost + costRemoved, length(twoNodeBundles)
    else
        # println("Reverting solution\n")
        revert_solution!(solution, instance, twoNodeBundles, oldPaths, oldBins)
        feasible ? print("x") : print("X")
        @assert is_feasible(instance, solution; verbose=true)
        return 0.0, 0
    end
end

# Increase direct costs a hundred fold and reintroduce directs 
function forbid_directs!(instance::Instance)
    # Multiplying by a constant factor the number of trucks precomputed for directs
    for bundle in instance.bundles
        for order in bundle.orders
            order.bpUnits[:direct] *= 100
        end
    end
end

# Revert direct cost to normal values and reintroduce all bundles
function allow_directs!(instance::Instance)
    for bundle in instance.bundles
        for order in bundle.orders
            order.bpUnits[:direct] /= 100
        end
    end
end

# Improvement possible for two node common incremental
# In the common path computation :
# - update only arcs that can be in a path from src to dst
#     - these don't change during execution so they can be pre-computed   
# - use the current costs to diversify the paths / solutions obtained
#     - can be made more efficient by having a second cost matrix for TTGraph to compute at the same cost the base cost and current cost

# Remove bundles flowing from src to dst, insert them back forcefully on the same path 
# then use bundle_reintroduction on each bundle in hope to improve the cost
function two_node_common_incremental!(
    solution::Solution,
    instance::Instance,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int};
    costThreshold::Float64=EPS,
)
    @assert is_feasible(instance, solution; verbose=true)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    twoNodeBundleIdxs = get_bundles_to_update(TTGraph, solution, src, dst)
    twoNodeBundles = instance.bundles[twoNodeBundleIdxs]
    # If there is no bundles concerned, returning
    length(twoNodeBundles) == 0 && return 0.0, 0
    # println(
    #     "\nUpdating bundles $twoNodeBundleIdxs between nodes $src and $dst and then full paths",
    # )
    fullOldPaths = solution.bundlePaths[twoNodeBundleIdxs]
    commonOldPaths = get_paths_to_update(solution, twoNodeBundles, src, dst)

    # The filtering could also occur in terms of cost removed : it must be above a certain threshold
    estimRemCost = sum(
        bundle_estimated_removal_cost(bundle, path, instance, solution) for
        (bundle, path) in zip(twoNodeBundles, fullOldPaths)
    )
    # println("Estimated (full) removal cost = $estimRemCost")
    estimRemCost <= costThreshold && return 0.0, 0

    # Saving previous bins and removing bundle 
    # In the worst case, you modify all paths of the bundles involved, 
    # which means you only need to store the old bins on the intersection of the old paths
    oldBins = save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, twoNodeBundles, fullOldPaths)
    )
    costRemoved = update_solution!(
        solution, instance, twoNodeBundles, commonOldPaths; remove=true
    )
    # println("Cost removed = $costRemoved")

    # Creating a unique bundle for all the bundles concerned
    commonBundle = fuse_bundles(instance, twoNodeBundles, CAPACITIES)
    # Inserting it back
    newPath, pathCost = greedy_insertion(
        solution,
        TTGraph,
        TSGraph,
        commonBundle,
        src,
        dst,
        CAPACITIES;
        sorted=true,
        findSources=false,
    )

    # Updating solution for the next step
    newPaths = [newPath for _ in 1:length(twoNodeBundles)]
    updateCost = update_solution!(solution, instance, twoNodeBundles, newPaths; sorted=true)
    improvement = updateCost + costRemoved
    bunCounter = length(twoNodeBundles)
    # println("New path : $newPath")
    # println("Cost added = $updateCost")

    # Inserting back concerned bundles
    # shuffle!(twoNodeBundleIdxs)
    for (i, bIdx) in enumerate(shuffle(twoNodeBundleIdxs))
        bundle = instance.bundles[bIdx]
        # println("Re-inserting bundle $bIdx")
        # Time lost here, but still need to only accept improving updates so as is seems fine
        improvement += bundle_reintroduction!(
            solution, instance, bundle, CAPACITIES; sorted=true, costThreshold=1.0
        )
        # println("Improvement = $improvement")
        # println("New path = $(solution.bundlePaths[bIdx])")
        i % 10 == 0 && print(".")
        (improvement < -1) && (bunCounter += 1)
    end

    # If no improvement at the end, reverting solution to its first state
    if improvement > 1e2
        # Slicing makes a copy implicitly
        newPaths = solution.bundlePaths[twoNodeBundleIdxs]
        revert_solution!(
            solution, instance, twoNodeBundles, fullOldPaths, oldBins, newPaths
        )
        print("x")
        # println("Reverting solution\n")
        @assert is_feasible(instance, solution; verbose=true)
        return 0.0, 0
    else
        print("o ($(round(improvement; digits=1)))")
        # println("Keeping new path\n")
        @assert is_feasible(instance, solution; verbose=true)
        return improvement, bunCounter
    end
end

function two_node_common_incremental2!(
    solution::Solution,
    instance::Instance,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int},
    CHANNEL::Channel{Vector{Int}};
    costThreshold::Float64=EPS,
)
    # startingFeasible = is_feasible(instance, solution)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    twoNodeBundleIdxs = get_bundles_to_update(TTGraph, solution, src, dst)
    twoNodeBundles = instance.bundles[twoNodeBundleIdxs]

    # TODO : change this to <= 1 to account for change in candidate nodes acceptance criteria for separated bundles

    length(twoNodeBundles) == 0 && return 0.0, 0
    fullOldPaths = solution.bundlePaths[twoNodeBundleIdxs]
    commonOldPaths = get_paths_to_update(solution, twoNodeBundles, src, dst)
    # The filtering could also occur in terms of cost removed : it must be above a certain threshold
    estimRemCost = sum(
        bundle_estimated_removal_cost(bundle, path, instance, solution) for
        (bundle, path) in zip(twoNodeBundles, fullOldPaths)
    )
    estimRemCost <= costThreshold && return 0.0, 0

    # startCost = compute_cost(instance, solution; verbose=false)
    # Saving previous bins and removing bundle 
    oldBins = save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, twoNodeBundles, fullOldPaths)
    )
    # testSol = deepcopy(solution)
    # costRemoved2 = update_solution!(
    #     testSol, instance, twoNodeBundles, commonOldPaths; remove=true
    # )
    costRemoved = 0.0
    for (bundle, path) in zip(twoNodeBundles, commonOldPaths)
        costRemoved += update_solution!(solution, instance, bundle, path; remove=true)
        # afterRemovalCost = compute_cost(instance, solution; verbose=false)
        # println("\nCost removal = $(costRemoved)")
        # println("Cost removal 2 = $(costRemoved2)")
        # println("Recomputed cost removal = $(afterRemovalCost - startCost)\n")
        # @assert isapprox(costRemoved, afterRemovalCost - startCost; atol=1.0)
    end

    # @assert isapprox(costRemoved, costRemoved2; atol=0.1) "costRemoved = $costRemoved / costRemoved2 = $costRemoved2"

    # afterRemovalCost = compute_cost(instance, solution; verbose=false)
    # @assert isapprox(costRemoved, afterRemovalCost - startCost; atol=1.0) "afterRemovalCost - startCost = $(afterRemovalCost - startCost) ($afterRemovalCost - $startCost) / costRemoved = $costRemoved"

    # Creating a unique bundle for all the bundles concerned
    commonBundle = fuse_bundles(instance, twoNodeBundles, CAPACITIES)
    # Inserting it back
    newPath, pathCost = greedy_insertion2(
        solution, TTGraph, TSGraph, commonBundle, src, dst, CHANNEL
    )
    # Updating solution for the next step
    newPaths = [newPath for _ in 1:length(twoNodeBundles)]
    updateCost = update_solution!(solution, instance, twoNodeBundles, newPaths; sorted=true)

    # afterReinsertionCost = compute_cost(instance, solution; verbose=false)
    # @assert isapprox(updateCost, afterReinsertionCost - afterRemovalCost; atol=1.0) "afterReinsertionCost - afterRemovalCost = $(afterReinsertionCost - afterRemovalCost) ($afterReinsertionCost - $afterRemovalCost) / updateCost = $updateCost"
    # @assert isapprox(pathCost, updateCost; atol=1.0) "pathCost = $pathCost / updateCost = $updateCost"

    # WARNING : Cost increase can happen after removal and re-introduction
    improvement = updateCost + costRemoved
    # @assert isapprox(improvement, afterReinsertionCost - startCost; atol=1.0) "afterReinsertionCost - startCost = $(afterReinsertionCost - startCost) ($afterReinsertionCost - $startCost) / improvement = $improvement"

    bunCounter = length(twoNodeBundles)
    # Inserting back concerned bundles
    for (i, bIdx) in enumerate(shuffle(twoNodeBundleIdxs))
        bundle = instance.bundles[bIdx]
        forceReIntro = !is_path_admissible(TTGraph, solution.bundlePaths[bIdx])
        improvement += bundle_reintroduction2!(
            solution,
            instance,
            bundle,
            CHANNEL;
            costThreshold=1.0,
            directReIntro=forceReIntro,
        )
        i % 100 == 0 && print(".")
        (improvement < -1) && (bunCounter += 1)
    end

    # afterBunReinsertCost = compute_cost(instance, solution; verbose=false)
    # @assert isapprox(improvement, afterBunReinsertCost - startCost; atol=1.0) "afterBunReinsertCost - startCost = $(afterBunReinsertCost - startCost) ($afterBunReinsertCost - $startCost) / improvement = $improvement"

    # If no improvement at the end, reverting solution to its first state
    if improvement > 1e2
        # Slicing makes a copy implicitly
        newPaths = solution.bundlePaths[twoNodeBundleIdxs]
        revert_solution!(
            solution, instance, twoNodeBundles, fullOldPaths, oldBins, newPaths
        )
        print("x")
        return 0.0, 0
    else
        if improvement < -1e3
            print("o ($(round(Int, improvement)))")
        elseif improvement < -1
            print("o")
        end
        return improvement, bunCounter
    end
end

function all_two_nodes!(
    solution::Solution,
    instance::Instance,
    srcNodes::Vector{Int},
    dstNodes::Vector{Int};
    threshold::Float64=EPS,
    timeLimit::Int=60,
    isShuffled::Bool=false,
)
    timeLimit > 0 || return nothing
    CAPACITIES = Int[]
    CHANNEL = create_filled_channel()
    startTime = time()
    twoNodeImprovement = 0.0
    twoNodeCounter, twoNodeTested, i = 0, 0, 0
    TTGraph = instance.travelTimeGraph
    percentIdx = ceil(Int, length(srcNodes) * length(dstNodes) / 100)
    barIdx = ceil(Int, percentIdx / 5)
    println("Two node incremental progress : (| = $barIdx combinations)")
    improvement, bunCounter = 0.0, 0
    if !isShuffled
        dstNodes = shuffle(dstNodes)
        srcNodes = shuffle(srcNodes)
    end
    for dst in dstNodes, src in srcNodes
        i += 1
        i % percentIdx == 0 && print(" $(round(Int, i / percentIdx))% ")
        i % barIdx == 0 && print("|")
        are_nodes_candidate(TTGraph, src, dst) || continue

        improvement, count = two_node_common_incremental2!(
            solution, instance, src, dst, CAPACITIES, CHANNEL; costThreshold=threshold
        )
        # print(" $src-$dst : $improvement")

        twoNodeTested += 1
        (improvement < -1e-1) && (twoNodeCounter += 1)
        (improvement < -1) && (bunCounter += count)
        twoNodeImprovement += improvement
        time() - startTime > timeLimit && break
    end
    println()
    @info "Total two-node improvement" :couples_computed = twoNodeTested :improved =
        twoNodeCounter :bundles_changed = bunCounter :improvement = twoNodeImprovement :time =
        round((time() - startTime) * 1000) / 1000
    return twoNodeImprovement, bunCounter
end

function loop_two_nodes!(
    solution::Solution, instance::Instance; threshold::Float64=EPS, timeLimit::Int=60
)
    timeLimit > 0 || return nothing
    CAPA, start, totImprov = Int[], time(), 0.0
    CHANNEL = create_filled_channel()
    improvCount, bunCount, tested, i = 0, 0, 0, 0
    TTGraph = instance.travelTimeGraph
    # Computing source and destination nodes
    srcNodes = TTGraph.commonNodes
    plantNodes = findall(x -> x.type == :plant, TTGraph.networkNodes)
    dstNodes = vcat(srcNodes, plantNodes)
    percentIdx = ceil(Int, length(srcNodes) * length(dstNodes) / 100)
    barIdx = ceil(Int, percentIdx / 5)
    println("Two node incremental progress : (| = $barIdx combinations)")
    while time() - start < timeLimit
        src, dst = rand(srcNodes), rand(dstNodes)
        while !are_nodes_candidate(TTGraph, src, dst)
            src, dst = rand(srcNodes), rand(dstNodes)
        end
        i += 1
        i % 1000 == 0 && print(" $i ")
        i % 100 == 0 && print("|")
        # Doing the thing
        improvement, count = two_node_common_incremental2!(
            solution, instance, src, dst, CAPA, CHANNEL; costThreshold=threshold
        )
        tested += 1
        (improvement < -1e-1) && (improvCount += 1)
        (improvement < -1) && (bunCount += count)
        totImprov += improvement
    end
    println()
    @info "Total two-node improvement" :couples_computed = tested :improved = improvCount :bundles_changed =
        bunCount :improvement = totImprov :time = round((time() - start) * 1000) / 1000
    return totImprov, bunCount
end

function local_search!(
    solution::Solution,
    instance::Instance;
    timeLimit::Int=300,
    stepTimeLimit::Int=60,
    firstLoop::Bool=true,
)
    # Combine the three small neighborhoods
    TTGraph = instance.travelTimeGraph
    sort_order_content!(instance)
    startCost = compute_cost(instance, solution)
    threshold = 5e-5 * startCost
    CAPACITIES = Int[]
    ALL_COMMODITIES = Commodity[]
    totalImprovement = 0.0

    startTime = time()
    remainingTime = round(Int, timeLimit - (time() - startTime))
    stepTimeLimit = min(stepTimeLimit, remainingTime)
    bundleIdxs = randperm(length(instance.bundles))
    totalImprovement += reintroduce_bundles!(
        solution, instance, bundleIdxs; costThreshold=threshold, timeLimit=stepTimeLimit
    )

    remainingTime = round(Int, timeLimit - (time() - startTime))
    stepTimeLimit = min(2 * stepTimeLimit, remainingTime)
    threshold = 5e-5 * compute_cost(instance, solution)
    srcNodes = TTGraph.commonNodes
    plantNodes = findall(x -> x.type == :plant, TTGraph.networkNodes)
    dstNodes = vcat(srcNodes, plantNodes)
    improv, count = all_two_nodes!(
        solution, instance, srcNodes, dstNodes; threshold=threshold, timeLimit=stepTimeLimit
    )
    totalImprovement += improv

    remainingTime = round(Int, timeLimit - (time() - startTime))
    stepTimeLimit = min(stepTimeLimit, remainingTime)
    bundleIdxs = randperm(length(instance.bundles))
    totalImprovement += reintroduce_bundles!(
        solution, instance, bundleIdxs; costThreshold=threshold, timeLimit=stepTimeLimit
    )

    # Finally, bin packing improvement to optimize packings
    startTime = time()
    improvement = bin_packing_improvement!(
        solution, instance, ALL_COMMODITIES, CAPACITIES; sorted=true
    )
    @info "Bin packing improvement" :improvement = improvement :time =
        round((time() - startTime) * 1000) / 1000
    totalImprovement += improvement
    @info "Full local search done" :total_improvement = totalImprovement

    return totalImprovement
end

function local_search2!(
    solution::Solution, instance::Instance; timeLimit::Int=300, stepTimeLimit::Int=60
)
    sort_order_content!(instance)
    threshold = 5e-5 * compute_cost(instance, solution)
    CAPA, COMMO = Int[], Commodity[]
    totImprov, noImprov = 0.0, 0
    # Looping while there is time
    startTime = time()
    while (time() - startTime < timeLimit) && (noImprov < 2)
        loopImprov = 0.0
        # Reintroduce bundle
        remainingTime = round(Int, timeLimit - (time() - startTime))
        limit = min(stepTimeLimit, remainingTime)
        bundleIdxs = randperm(length(instance.bundles))
        loopImprov += reintroduce_bundles!(
            solution, instance, bundleIdxs; costThreshold=threshold, timeLimit=limit
        )
        # Two node common incremental 
        remainingTime = round(Int, timeLimit - (time() - startTime))
        limit = min(2 * stepTimeLimit, remainingTime)
        loopImprov += loop_two_nodes!(
            solution, instance; threshold=threshold, timeLimit=limit
        )[1]
        # Recording useless step 
        (loopImprov < 1e-3) && (noImprov += 1)
        totImprov += loopImprov
    end
    # Finally, bin packing improvement to optimize packings
    startTime = time()
    improvement = bin_packing_improvement!(solution, instance, COMMO, CAPA; sorted=true)
    @info "Bin packing improvement" :improvement = improvement :time = round(
        (time() - startTime); digits=2
    )
    totImprov += improvement
    @info "Full local search done" :total_improvement = totImprov
    return totImprov
end

function local_search3!(
    solution::Solution, instance::Instance; timeLimit::Int=300, stepTimeLimit::Int=60
)
    sort_order_content!(instance)
    startCost = compute_cost(instance, solution)
    threshold = 5e-5 * startCost
    CAPA, COMMO = Int[], Commodity[]
    CHANNEL = create_filled_channel()
    totImprov, noImprov, i = 0.0, 0, 0
    TTGraph = instance.travelTimeGraph
    srcNodes = TTGraph.commonNodes
    plantNodes = findall(x -> x.type == :plant, TTGraph.networkNodes)
    dstNodes = vcat(srcNodes, plantNodes)
    # Looping while there is time
    startTime = time()
    maxIter = 150_000
    noImprovLimit = min(5000, 3 * length(instance.bundles))
    while (time() - startTime < timeLimit) && (i <= maxIter) && (noImprov < noImprovLimit)
        startLoopImprov = totImprov
        # Make the probability of the neighborhood vary with time ? skewed towards bundle reintroduction ? 
        # Choosing random neighborhood between bundle reintroduction and two_node_common_incremental
        if rand() < 0.5
            # Bundle reintroduction
            bundle = instance.bundles[rand(1:length(instance.bundles))]
            totImprov += bundle_reintroduction2!(
                solution, instance, bundle, CHANNEL; costThreshold=threshold
            )
        else
            # Two node common incremental
            src, dst = rand(srcNodes), rand(dstNodes)

            # TODO : for bundles separated by parts, (suppliers, plants) couples should also be candidate

            while !are_nodes_candidate(TTGraph, src, dst) &&
                (time() - startTime < timeLimit)
                src, dst = rand(srcNodes), rand(dstNodes)
            end
            improvement, count = two_node_common_incremental2!(
                solution, instance, src, dst, CAPA, CHANNEL; costThreshold=threshold
            )
            totImprov += improvement
        end
        # Recording useless step
        if isapprox(totImprov, startLoopImprov; atol=1.0)
            noImprov += 1
        else
            noImprov = 0
        end
        # Printing progress
        i += 1
        i % 100 == 0 && print("|")
        i % 1000 == 0 && print(" $i ")
    end
    println(
        "\nLoop Break : time = $(round(time() - startTime; digits=1)), i = $i, noImprov = $noImprov",
    )
    # Finally, bin packing improvement to optimize packings
    bpStartTime = time()
    improvement = bin_packing_improvement!(solution, instance, COMMO, CAPA; sorted=true)
    @info "Bin packing improvement" :improvement = improvement :time = round(
        (time() - bpStartTime); digits=2
    )
    totImprov += improvement
    finalCost = compute_cost(instance, solution)
    if !isapprox(totImprov, finalCost - startCost; atol=1.0)
        @warn "Improvement computed inside local search is different from the one computed outside" :totImprov =
            totImprov :realImprov = (finalCost - startCost)
        totImprov = finalCost - startCost
    end
    relImprov = round(totImprov / startCost * 100; digits=2)
    timeTaken = round(time() - startTime; digits=2)
    feasible = is_feasible(instance, solution)
    @info "Full local search done" :total_improvement = totImprov :relative_improvement =
        relImprov :time = timeTaken :feasible = feasible
    return totImprov
end

function local_search4!(
    solution::Solution, instance::Instance; timeLimit::Int=300, stepTimeLimit::Int=60
)
    sort_order_content!(instance)
    startCost = compute_cost(instance, solution)
    threshold = 5e-5 * startCost
    CAPA, COMMO = Int[], Commodity[]
    CHANNEL = create_filled_channel()
    totImprov, noImprov, i = 0.0, 0, 0
    TTGraph = instance.travelTimeGraph
    srcNodes = TTGraph.commonNodes
    plantNodes = findall(x -> x.type == :plant, TTGraph.networkNodes)
    dstNodes = vcat(srcNodes, plantNodes)
    # Looping while there is time
    startTime, restarts = time(), 0
    noImprovLimit = length(instance.bundles)
    I = Int[]
    while (time() - startTime < timeLimit) && (restarts < 3)
        noImprov, i = 0, 0
        bundleIdxs = randperm(length(instance.bundles))
        remainingTime = round(Int, timeLimit - (time() - startTime))
        totImprov += reintroduce_bundles!(
            solution, instance, bundleIdxs; timeLimit=remainingTime
        )
        while (noImprov < noImprovLimit) && (time() - startTime < timeLimit)
            startLoopImprov = totImprov
            # Choosing random neighborhood between bundle reintroduction and two_node_common_incremental
            if rand() < 0.5
                # Bundle reintroduction
                bundle = instance.bundles[bundleIdxs[i % length(bundleIdxs) + 1]]
                totImprov += bundle_reintroduction2!(
                    solution, instance, bundle, CHANNEL; costThreshold=threshold
                )
            else
                # Two node common incremental
                src, dst = rand(srcNodes), rand(dstNodes)
                # src, dst = 150, 352
                while !are_nodes_candidate(TTGraph, src, dst) &&
                    (time() - startTime < timeLimit)
                    src, dst = rand(srcNodes), rand(dstNodes)
                end
                improvement, count = two_node_common_incremental2!(
                    solution, instance, src, dst, CAPA, CHANNEL; costThreshold=threshold
                )
                totImprov += improvement
            end
            # Recording non improving step
            noImprov = isapprox(totImprov, startLoopImprov; atol=1.0) ? noImprov + 1 : 0
            # Printing progress
            i += 1
            i % 100 == 0 && print("|")
            i % 1000 == 0 && print(" $i ")
        end
        restarts += 1
        push!(I, i)
    end
    println(
        "\nLoop Break : time = $(round(time() - startTime; digits=1)), i = $I, noImprov = $noImprov",
    )
    # Finally, bin packing improvement to optimize packings
    bpStartTime = time()
    improvement = bin_packing_improvement!(solution, instance, COMMO, CAPA)
    @info "Bin packing improvement" :improvement = improvement :time = round(
        (time() - bpStartTime); digits=2
    )
    totImprov += improvement
    finalCost = compute_cost(instance, solution)
    if !isapprox(totImprov, finalCost - startCost; atol=1.0)
        @warn "Improvement computed inside local search is different from the one computed outside" :totImprov =
            totImprov :realImprov = (finalCost - startCost)
        totImprov = finalCost - startCost
    end
    relImprov = round(totImprov / startCost * 100; digits=2)
    timeTaken = round(time() - startTime; digits=2)
    feasible = is_feasible(instance, solution)
    @info "Full local search done" :total_improvement = totImprov :relative_improvement =
        relImprov :time = timeTaken :feasible = feasible
    return totImprov
end

# A first modification could be to change the double loop on all_two_nodes to a single loop that stops after a certain amount of time

# Maybe what we want is to alternate between :
# - force bundles on the common network
# - use all_two_nodes for a certain amount of time
# - reintroduce all bundles
# - use all_two_nodes for a certain amount of time

function large_local_search!(
    solution::Solution, instance::Instance; timeLimit::Int=300, stepTimeLimit::Int=60
)
    println()
    @info "Starting large local search"
    println()

    TTGraph = instance.travelTimeGraph
    sort_order_content!(instance)
    startCost = compute_cost(instance, solution)
    startTime = time()
    threshold = 5e-5 * startCost
    totalImprovement = 0.0

    # Forbidding the directs to force consolidation
    forbid_directs!(instance)
    # Reintroducing only directs
    remainingTime = round(Int, timeLimit - (time() - startTime))
    stepTimeLimit = min(stepTimeLimit, remainingTime)
    bundleIdxs = randperm(length(instance.bundles))
    filter!(x -> length(solution.bundlePaths[x]) == 2, bundleIdxs)
    directsBefore = length(bundleIdxs)
    reintroduce_bundles!(
        solution,
        instance,
        bundleIdxs;
        costThreshold=threshold,
        timeLimit=stepTimeLimit,
        directReIntro=true,
    )
    directsAfter = count(x -> length(solution.bundlePaths[x]) == 2, bundleIdxs)

    # Optimizing common network with two node common incremental
    remainingTime = round(Int, timeLimit - (time() - startTime))
    stepTimeLimit = min(stepTimeLimit, remainingTime)
    srcNodes = TTGraph.commonNodes
    plantNodes = findall(x -> x.type == :plant, TTGraph.networkNodes)
    dstNodes = vcat(srcNodes, plantNodes)
    threshold = 5e-5 * compute_cost(instance, solution)
    loop_two_nodes!(solution, instance; threshold=threshold, timeLimit=2 * stepTimeLimit)

    totalImprovement += compute_cost(instance, solution) - startCost
    @info "Enlarging step done" :direct_after = directsAfter :directs_removed = (
        directsBefore - directsAfter
    ) :improvement = totalImprovement :time = round((time() - startTime) * 1000) / 1000

    # Re-allowing to get the best cost
    allow_directs!(instance)
    # The rest is a classic local search
    # remainingTime = timeLimit - (time() - startTime)
    remainingTime = timeLimit
    lsImprovement = local_search3!(
        solution, instance; timeLimit=remainingTime, stepTimeLimit=stepTimeLimit
    )
    totalImprovement += lsImprovement
    @info "Full large local search done" :total_improvement = totalImprovement :time =
        round((time() - startTime) * 1000) / 1000
    return totalImprovement
end
