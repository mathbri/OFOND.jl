# Solution structure

# Updating bins and loads in bin packing file

struct Solution
    # Paths used for delivery
    bundlePaths::Vector{Vector{Int}}
    bundlesOnNode::Dict{Int,Vector{Bundle}} # bundles on each node of the travel-time common graph + plants
    # Transport units completion through time 
    bins::SparseMatrixCSC{Vector{Bin},Int}
end

function Solution(
    travelTimeGraph::TravelTimeGraph,
    timeSpaceGraph::TimeSpaceGraph,
    bundles::Vector{Bundle},
)
    plants = findall(node -> node.type == :plant, travelTimeGraph.networkNodes)
    keys = vcat(travelTimeGraph.commonNodes, plants)
    I, J, V = findnz(timeSpaceGraph.networkArcs)
    bins = [Bin[] for _ in I]
    return Solution(
        fill([-1], length(bundles)),
        Dict{Int,Vector{Bundle}}(zip(keys, [Bundle[] for _ in keys])),
        sparse(I, J, bins),
    )
end

function Solution(instance::Instance)
    return Solution(instance.travelTimeGraph, instance.timeSpaceGraph, instance.bundles)
end

# Methods

function update_bundle_path!(
    solution::Solution, bundle::Bundle, path::Vector{Int}; partial::Bool
)
    oldPath = deepcopy(solution.bundlePaths[bundle.idx])
    if partial
        srcIdx = findfirst(node -> node == path[1], oldPath)
        dstIdx = findlast(node -> node == path[end], oldPath)
        path = vcat(oldPath[1:srcIdx], path[2:(end - 1)], oldPath[dstIdx:end])
    end
    solution.bundlePaths[bundle.idx] = path
    return oldPath
end

function update_bundle_on_nodes!(
    solution::Solution, bundle::Bundle, path::Vector{Int}; partial::Bool, remove::Bool=false
)
    if partial
        path = path[2:(end - 1)]
    end
    for node in path
        bundleVector = get(solution.bundlesOnNode, node, Bundle[])
        if remove
            filter!(bun -> bun != bundle, bundleVector)
        else
            push!(bundleVector, bundle)
        end
    end
end

# Add / Replace the path of the bundle in the solution with the path given as argument 
# If src and dst are referenced, replace the src-dst part of the current path with the new one
function add_path!(
    solution::Solution, bundle::Bundle, path::Vector{Int}; partial::Bool=false
)
    update_bundle_path!(solution, bundle, path; partial=partial)
    return update_bundle_on_nodes!(solution, bundle, path; partial=partial)
end

# Remove the path of the bundle in the solution
function remove_path!(solution::Solution, bundle::Bundle; src::Int=-1, dst::Int=-1)
    partial = (src != -1) && (dst != -1)
    oldPart = update_bundle_path!(solution, bundle, [src, dst]; partial=partial)
    return update_bundle_on_nodes!(solution, bundle, oldPart; partial=partial, remove=true)
end

# Plot some of the paths on a map ?
# Compute some import statistics ? (the ones in solution indicators for ex)
function analyze_solution() end

# Checking the number of paths
function check_enough_paths(instance::Instance, solution::Solution; verbose::Bool)
    if length(instance.bundles) != length(solution.bundlePaths)
        verbose &&
            @warn "Infeasible solution : $(length(instance.bundles)) bundles and $(length(solution.bundlePaths)) paths"
        return false
    end
    return true
end

# Checking the supplier is correct
function check_supplier(instance::Instance, bundle::Bundle, pathSrc::Int; verbose::Bool)
    pathSupplier = instance.travelTimeGraph.networkNodes[pathSrc]
    if bundle.supplier != pathSupplier
        verbose &&
            @warn "Infeasible solution : bundle $(bundle.idx) has supplier $(bundle.supplier) and its path starts at $(pathSupplier)"
        return false
    end
    return true
end

# Checking the customer is correct
function check_customer(instance::Instance, bundle::Bundle, pathDst::Int; verbose::Bool)
    pathCustomer = instance.travelTimeGraph.networkNodes[pathDst]
    if bundle.customer != pathCustomer
        verbose &&
            @warn "Infeasible solution : bundle $(bundle.idx) has customer $(bundle.customer) and its path ends at $(pathCustomer)"
        return false
    end
    return true
end

function get_routed_commodities(
    solution::Solution, order::Order, timedSrc::Int, timedDst::Int
)
    allArcCommodities = get_all_commodities(solution.bins[timedSrc, timedDst])
    orderUniqueCom = unique(order.content)
    return sort(filter(com -> com in orderUniqueCom, allArcCommodities))
end

function check_quantities(
    instance::Instance, solution::Solution, src::Int, dst::Int, order::Order; verbose::Bool
)
    timedSrc, timedDst = time_space_projector(
        instance.travelTimeGraph, instance.timeSpaceGraph, src, dst, order.deliveryDate
    )
    # Checking quantities in this arc
    routedCommodities = get_routed_commodities(solution, order, timedSrc, timedDst)
    if sort(order.content) != routedCommodities
        verbose &&
            @warn "Infeasible solution : order $order misses quantities on arc ($timedSrc-$timedDst)" :inOrder =
                order.content :onArc = routedCommodities
        return false
    end
    return true
end

# Check whether a solution is feasible or not 
function is_feasible(instance::Instance, solution::Solution; verbose::Bool=false)
    check_enough_paths(instance, solution; verbose=verbose) || return false
    # All commodities are delivered : start from supplier with right quantities, and arrives at customer, with right quantities
    for bundle in instance.bundles
        bundlePath = solution.bundlePaths[bundle.idx]
        pathSrc, pathDst = bundlePath[1], bundlePath[end]
        check_supplier(instance, bundle, pathSrc; verbose=verbose) || return false
        check_customer(instance, bundle, pathDst; verbose=verbose) || return false
        # Checking that the right quantities are associated
        for order in bundle.orders
            pathOutSrc, pathInDst = bundlePath[2], bundlePath[end - 1]
            check_quantities(
                instance, solution, pathSrc, pathOutSrc, order; verbose=verbose
            ) || return false
            check_quantities(
                instance, solution, pathInDst, pathDst, order; verbose=verbose
            ) || return false
        end
    end
    return true
end

# Detect all infeasibility in a solution

function detect_infeasibility(instance::Instance, solution::Solution)
    check_enough_paths(instance, solution; verbose=true)
    # All commodities are delivered : start from supplier with right quantities, and arrives at customer, with right quantities
    for bundle in instance.bundles
        bundlePath = solution.bundlePaths[bundle.idx]
        pathSrc, pathDst = bundlePath[1], bundlePath[end]
        check_supplier(instance, bundle, pathSrc; verbose=true)
        check_customer(instance, bundle, pathDst; verbose=true)
        # Checking that the right quantities are associated
        for order in bundle.orders
            pathOutSrc, pathInDst = bundlePath[2], bundlePath[end - 1]
            check_quantities(instance, solution, pathSrc, pathOutSrc, order; verbose=true)
            check_quantities(instance, solution, pathInDst, pathDst, order; verbose=true)
        end
    end
end

# Compute arc cost with respect to the bins on it
function compute_arc_cost(
    TSGraph::TimeSpaceGraph, bins::Vector{Bin}, src::Int, dst::Int; current_cost::Bool
)
    dstData, arcData = TSGraph.networkNodes[dst], TSGraph.networkArcs[src, dst]
    # Computing useful quantities
    arcVolume = sum(arcData.capacity - bin.capacity for bin in bins) / VOLUME_FACTOR
    arcLeadTimeCost = sum(sum(com.leadTimeCost for com in bin) for bin in bins)
    # Node cost 
    cost = (dstData.volumeCost + arcData.carbonCost) * arcVolume
    # Transport cost 
    transportUnits = arcData.isLinear ? (arcVolume / arcData.capacity) : length(bins)
    transportCost = current_cost ? TSGraph.currentCost[src, dst] : arcData.unitCost
    cost += transportUnits * transportCost
    # Commodity cost
    return cost += arcData.distance * arcLeadTimeCost
end

# Compute the cost of a solution : node cost + arc cost + commodity cost
function compute_cost(instance::Instance, solution::Solution; current_cost::Bool=false)
    totalCost = 0.0
    for arc in edges(instance.timeSpaceGraph)
        arcBins = solution.bins[src(arc), dst(arc)]
        # If there is no bins, skipping arc
        length(arcBins) == 0 && continue
        # Arc cost
        totalCost += compute_arc_cost(
            instance.timeSpaceGraph, arcBins, src(arc), dst(arc); current_cost=current_cost
        )
    end
    return totalCost
end
