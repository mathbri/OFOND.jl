# Local search heuristic and building blocks

# For the minimal flow on maritime arcs, one solution is to check at removal time if the quantities left satisfy the minimal flow, if not just recomuting path to and from oversea arc 
# At insertion time, if the added flow don't make enough for the constraint, arc is forbidden (INF) cost
# Another option for insertion is to make a first round of insertion without constraint and if there is arcs that does not satisfy, 
#    - take all bundles of it, forbid arc for every one and recompute insertion and repaeat until constraint are good

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
    costImprov, computedNoImprov, computable, candidate = 0.0, 0, 0, 0
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
    return costImprov
end

# Parallel version of the bin packing improvement
function parallel_bin_packing_improvement!(
    solution::Solution, instance::Instance; sorted::Bool=false, skipLinear::Bool=true
)
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

# Removing and inserting back the bundle in the solution.
# If the operation did not lead to a cost improvement, reverting back to the former state of the solution.
function bundle_reintroduction!(
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
    # Saving previous bins and removing bundle
    oldBins = save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, [bundle], [oldPath])
    )
    costRemoved = update_solution!(solution, instance, bundle, oldPath; remove=true)
    # Inserting it back
    suppNode = TTGraph.bundleSrc[bundle.idx]
    custNode = TTGraph.bundleDst[bundle.idx]
    newPath, pathCost = greedy_insertion(
        solution, TTGraph, TSGraph, bundle, suppNode, custNode, CHANNEL
    )
    # Updating path if it improves the cost (accounting for EPS cost on arcs)
    if pathCost + costRemoved < -1e-3 || directReIntro
        # Adding to solution
        update_solution!(solution, instance, bundle, newPath; sorted=true)
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
        improvement = bundle_reintroduction!(
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
    timeTaken = round((time() - start) * 1000) / 1000
    @info "Total bundle re-introduction improvement" :bundles_updated = count :improvement =
        totImpro :time = timeTaken :feasible = feasible
    return totImpro
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
    CAPACITIES::Vector{Int},
    CHANNEL::Channel{Vector{Int}};
    costThreshold::Float64=EPS,
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    twoNodeBundleIdxs = get_bundles_to_update(TTGraph, solution, src, dst)
    twoNodeBundles = instance.bundles[twoNodeBundleIdxs]
    length(twoNodeBundles) == 0 && return 0.0, 0
    fullOldPaths = solution.bundlePaths[twoNodeBundleIdxs]
    commonOldPaths = get_paths_to_update(solution, twoNodeBundles, src, dst)
    # The filtering could also occur in terms of cost removed : it must be above a certain threshold
    estimRemCost = sum(
        bundle_estimated_removal_cost(bundle, path, instance, solution) for
        (bundle, path) in zip(twoNodeBundles, fullOldPaths)
    )
    estimRemCost <= costThreshold && return 0.0, 0
    # Saving previous bins and removing bundle 
    oldBins = save_previous_bins(
        solution, get_bins_updated(TSGraph, TTGraph, twoNodeBundles, fullOldPaths)
    )
    costRemoved = update_solution!(
        solution, instance, twoNodeBundles, commonOldPaths; remove=true
    )
    # Creating a unique bundle for all the bundles concerned
    commonBundle = fuse_bundles(instance, twoNodeBundles, CAPACITIES)
    # Inserting it back
    newPath, pathCost = greedy_insertion(
        solution, TTGraph, TSGraph, commonBundle, src, dst, CHANNEL
    )
    # Updating solution for the next step
    newPaths = [newPath for _ in 1:length(twoNodeBundles)]
    updateCost = update_solution!(solution, instance, twoNodeBundles, newPaths; sorted=true)
    improvement = updateCost + costRemoved
    bunCounter = length(twoNodeBundles)
    # Inserting back concerned bundles
    for (i, bIdx) in enumerate(shuffle(twoNodeBundleIdxs))
        bundle = instance.bundles[bIdx]
        forceReIntro = !is_path_admissible(TTGraph, solution.bundlePaths[bIdx])
        improvement += bundle_reintroduction!(
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
        end
        return improvement, bunCounter
    end
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
        improvement, count = two_node_common_incremental!(
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
    solution::Solution, instance::Instance; timeLimit::Int=300, stepTimeLimit::Int=60
)
    sort_order_content!(instance)
    threshold = 5e-5 * compute_cost(instance, solution)
    CAPA, COMMO = Int[], Commodity[]
    CHANNEL = create_filled_channel()
    totImprov, noImprov, i = 0.0, 0, 0
    TTGraph = instance.travelTimeGraph
    srcNodes = TTGraph.commonNodes
    plantNodes = findall(x -> x.type == :plant, TTGraph.networkNodes)
    dstNodes = vcat(srcNodes, plantNodes)
    # Looping while there is time
    startTime = time()
    while (time() - startTime < timeLimit) && (i <= 150_000) && (noImprov < 5000)
        startLoopImprov = totImprov
        # Choosing random neighborhood between bundle reintroduction and two_node_common_incremental
        if rand() < 0.5
            # Bundle reintroduction
            bundle = instance.bundles[rand(1:length(instance.bundles))]
            totImprov += bundle_reintroduction!(
                solution, instance, bundle, CHANNEL; costThreshold=threshold
            )
        else
            # Two node common incremental
            src, dst = rand(srcNodes), rand(dstNodes)
            while !are_nodes_candidate(TTGraph, src, dst)
                src, dst = rand(srcNodes), rand(dstNodes)
            end
            improvement, count = two_node_common_incremental!(
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
    startTime = time()
    improvement = parallel_bin_packing_improvement!(solution, instance; sorted=true)
    @info "Bin packing improvement" :improvement = improvement :time = round(
        (time() - startTime); digits=2
    )
    totImprov += improvement
    finalCost = compute_cost(instance, solution)
    if !isapprox(totImprov, finalCost - startCost; atol=1.0)
        @warn "Improvement computed inside local search is different from the one computed outside" :totImprov =
            totImprov :realImprov = (finalCost - startCost)
    end
    @info "Full local search done" :total_improvement = totImprov :time = round(
        (time() - startTime); digits=2
    )
    return totImprov
end

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
    remainingTime = timeLimit
    lsImprovement = local_search!(
        solution, instance; timeLimit=remainingTime, stepTimeLimit=stepTimeLimit
    )
    totalImprovement += lsImprovement
    @info "Full large local search done" :total_improvement = totalImprovement :time =
        round((time() - startTime) * 1000) / 1000
    return totalImprovement
end
