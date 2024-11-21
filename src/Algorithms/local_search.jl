# Local search heuristic and building blocks

# For the minimal flow on maritime arcs, one solution is to check at removal time if the quantities left satisfy the minimal flow, if not just recomuting path to and from oversea arc 
# At insertion time, if the added flow don't make enough for the constraint, arc is forbidden (INF) cost
# Another option for insertion is to make a first round of insertion without constraint and if there is arcs that does not satisfy, 
#    - take all bundles of it, forbid arc for every one and recompute insertion and repaeat until constraint are good

# When we will split bundles, a new neighborhhod based on the perturb than optimize is to a full path for the old bundle and then reintroduce with the new bundles
# It can also be done between two nodes of the shared network 

# TODO : remove feasibility assertions in production

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
    # TODO : use the following if edges(...) is a bottleneck
    # Efficient iteration over sparse matrices
    # rows = rowvals(workingArcs)
    # for timedDst in 1:Base.size(workingArcs, 2)
    #     for srcIdx in nzrange(workingArcs, timedDst)
    #         timedSrc = rows[srcIdx]
    for arc in edges(instance.timeSpaceGraph.graph)
        arcBins = solution.bins[src(arc), dst(arc)]
        arcData = instance.timeSpaceGraph.networkArcs[src(arc), dst(arc)]
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
        bin_packing = ffdBins < bfdBins ? first_fit_decreasing! : best_fit_decreasing!
        empty!(arcBins)
        bin_packing(arcBins, arcData.capacity, allCommodities)
        # Computing cost improvement (unless linear arc)
        arcData.isLinear && continue
        costImprov -= arcData.unitCost * (lengthBefore - min(ffdBins, bfdBins))
    end
    println("All packings computable : $computable")
    println("Computed packings (lower bound not reached) : $candidate")
    println("Computed packings with no improvement : $computedNoImprov")
    # @assert is_feasible(instance, solution; verbose=true)
    return costImprov
end

# TODO : add the complete list of arcs to the time space graph if its creation / collection takes too much time
# TODO : make buffers for all commodities / capacities channel if allocation takes too much time
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
    counts = tmapreduce(.+, collect(edges(instance.timeSpaceGraph.graph))) do arc
        arcBins = solution.bins[src(arc), dst(arc)]
        arcData = instance.timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        # If no improvement possible
        if !is_bin_candidate(arcBins, arcData; skipLinear=skipLinear)
            # Returning if the bin was computable
            0.0, 0, length(arcBins) > 1, 0
        else
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
                bin_packing =
                    ffdBins < bfdBins ? first_fit_decreasing! : best_fit_decreasing!
                empty!(arcBins)
                bin_packing(arcBins, arcData.capacity, allCommodities; sorted=true)
                # Computing cost improvement (unless linear arc)
                if arcData.isLinear
                    0.0, 0, true, 1
                else
                    -arcData.unitCost * (lengthBefore - min(ffdBins, bfdBins)), 0, true, 1
                end
            end
        end
    end
    costImprov, computedNoImprov, computable, candidate = counts
    println("All packings computable : $computable")
    println("Computed packings (lower bound not reached) : $candidate")
    println("Computed packings with no improvement : $computedNoImprov")
    # @assert is_feasible(instance, solution; verbose=true)
    return costImprov
end

# TODO : if I store the order in which the bundles were inserted on the arcs, there is no need to gather all commodities in refilling : another "global" matrix to use for all computations ? or update solutions with remove returns the previous order insertion matrix of the solution
# The problem being that cost increase in removal than insertion goes up to 200 000 for world instance
# But if the bin packing improvement neighborhood change the bin filling, this order no longer makes sense
# So need to remove it if the bin pack found better solution

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
    if pathCost + costRemoved < -1e-3
        # println("Updating path\n")
        # Adding to solution
        update_solution!(solution, instance, bundle, newPath; sorted=sorted)
        # @assert is_feasible(instance, solution; verbose=true)
        return pathCost + costRemoved
    else
        # println("Reverting solution\n")
        revert_solution!(solution, instance, [bundle], [oldPath], oldBins)
        # @assert is_feasible(instance, solution; verbose=true)
        return 0.0
    end
end

# TODO : adapt tests to new return type
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
    shuffle!(twoNodeBundleIdxs)
    for (i, bIdx) in enumerate(twoNodeBundleIdxs)
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
        print("o")
        # println("Keeping new path\n")
        @assert is_feasible(instance, solution; verbose=true)
        return improvement, bunCounter
    end
end

# TODO : things that could be done also is to reintroduce bundles, than two node same path than reintroduce bundles
# than two node oncremental than bin pack improv
# This needs testing to see if the added computation time is worth it

# TODO : test with incremental and then with common as the first step to consolidate and choose the best one

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

    # The first loop on bundle reintroduction is optional
    if firstLoop
        bunCounter = 0
        startTime = time()
        bundleIdxs = randperm(length(instance.bundles))
        print("Bundle reintroduction progress : ")
        percentIdx = ceil(Int, length(bundleIdxs) / 100)
        for (i, bundleIdx) in enumerate(bundleIdxs)
            bundle = instance.bundles[bundleIdx]
            improvement = bundle_reintroduction!(
                solution, instance, bundle, CAPACITIES; sorted=true, costThreshold=threshold
            )
            i % 10 == 0 && print("|")
            i % percentIdx == 0 && print(" $(round(Int, i * 100 / length(bundleIdxs)))% ")
            # loopImprovement += improvement
            totalImprovement += improvement
            improvement < -1e-3 && (bunCounter += 1)
            time() - startTime > stepTimeLimit && break
        end
        println()
        feasible = is_feasible(instance, solution)
        @info "Total bundle re-introduction improvement" :bundles_updated = bunCounter :improvement =
            totalImprovement :time = round((time() - startTime) * 1000) / 1000 :feasible =
            feasible
    end

    # First, two node incremental to consolidate on shared network
    startTime = time()
    twoNodeImprovement = 0.0
    twoNodeCounter = 0
    twoNodeTested = 0
    plantNodes = findall(x -> x.type == :plant, TTGraph.networkNodes)
    two_node_nodes = vcat(TTGraph.commonNodes, plantNodes)
    threshold = 5e-5 * compute_cost(instance, solution)
    i = 0
    percentIdx = ceil(Int, length(two_node_nodes) * length(TTGraph.commonNodes) / 100)
    barIdx = ceil(Int, percentIdx / 5)
    println("Two node incremental progress : (| = $barIdx combinations)")
    improvement, bunCounter = 0.0, 0
    for dst in shuffle(two_node_nodes), src in shuffle(TTGraph.commonNodes)
        i += 1
        i % percentIdx == 0 && print(
            " $(round(Int, i * 100 / (length(two_node_nodes) * length(TTGraph.commonNodes))))% ",
        )
        i % barIdx == 0 && print("|")
        are_nodes_candidate(TTGraph, src, dst) || continue

        improvement, count = two_node_incremental!(
            solution, instance, src, dst, CAPACITIES; costThreshold=threshold
        )

        twoNodeTested += 1
        (improvement < -1e-1) && (twoNodeCounter += 1)
        (improvement < -1) && (bunCounter += count)
        twoNodeImprovement += improvement
        totalImprovement += improvement
        time() - startTime > stepTimeLimit && break
    end
    println()
    @info "Total two-node improvement" :couples_computed = twoNodeTested :improved =
        twoNodeCounter :bundles_changed = bunCounter :improvement = twoNodeImprovement :time =
        round((time() - startTime) * 1000) / 1000

    # Second, two node incremental to optimize shared network
    startTime = time()
    twoNodeImprovement = 0.0
    twoNodeCounter = 0
    twoNodeTested = 0
    plantNodes = findall(x -> x.type == :plant, TTGraph.networkNodes)
    two_node_nodes = vcat(TTGraph.commonNodes, plantNodes)
    i = 0
    percentIdx = ceil(Int, length(two_node_nodes) * length(TTGraph.commonNodes) / 100)
    barIdx = ceil(Int, percentIdx / 5)
    println("Two node common incremental progress : (| = $barIdx combinations)")
    for dst in shuffle(two_node_nodes), src in shuffle(TTGraph.commonNodes)
        i += 1
        i % percentIdx == 0 && print(
            " $(round(Int, i * 100 / (length(two_node_nodes) * length(TTGraph.commonNodes))))% ",
        )
        i % barIdx == 0 && print("|")
        are_nodes_candidate(TTGraph, src, dst) || continue
        improvement, count = two_node_common_incremental!(
            solution, instance, src, dst, CAPACITIES; costThreshold=threshold
        )
        twoNodeTested += 1
        (improvement < -1e-1) && (twoNodeCounter += 1)
        (improvement < -1) && (bunCounter += count)
        twoNodeImprovement += improvement
        totalImprovement += improvement
        # More time beacuse helps a lot
        time() - startTime > 2 * stepTimeLimit && break
    end
    println()
    @info "Total two-node improvement" :couples_computed = twoNodeTested :improved =
        twoNodeCounter :bundles_changed = bunCounter :improvement = twoNodeImprovement :time =
        round((time() - startTime) * 1000) / 1000

    # Bundle reintroduction at last
    startTime = time()
    bundleIdxs = randperm(length(instance.bundles))
    bunCounter = 0
    print("Bundle reintroduction progress : ")
    percentIdx = ceil(Int, length(bundleIdxs) / 100)
    threshold = 5e-5 * startCost
    reintroImprov = 0.0
    # Bundle reintroduction at last 
    for (i, bundleIdx) in enumerate(bundleIdxs)
        bundle = instance.bundles[bundleIdx]
        improvement = bundle_reintroduction!(
            solution, instance, bundle, CAPACITIES; sorted=true, costThreshold=threshold
        )
        i % 10 == 0 && print("|")
        i % percentIdx == 0 && print(" $(round(Int, i * 100 / length(bundleIdxs)))% ")
        reintroImprov += improvement
        totalImprovement += improvement
        improvement < -1e-3 && (bunCounter += 1)
        time() - startTime > stepTimeLimit && break
    end
    println()
    feasible = is_feasible(instance, solution)
    @info "Total bundle re-introduction improvement" :bundles_updated = bunCounter :improvement =
        reintroImprov :time = round((time() - startTime) * 1000) / 1000 :feasible = feasible

    # Finally, bin packing improvement to optimize packings
    startTime = time()
    improvement = bin_packing_improvement!(
        solution, instance, ALL_COMMODITIES, CAPACITIES; sorted=true
    )
    @info "Bin packing improvement" :improvement = improvement :time =
        round((time() - startTime) * 1000) / 1000
    totalImprovement += improvement
    @info "Full local search step done" :total_improvement = totalImprovement
    return totalImprovement
end