# Utils function for the large neighborhood search

# For arcs in the time-space network :
#     Update the current cost with the following mechanism :
#         Compute an actual volume cost : volume_cost = (unit_cost * nb_of_units) / total_volume_in_units
#         Compute the updated unit cost : unit cost = unit_capacity * volume_cost
# Use this new costs in all the other heuristics

# TODO : break into two files, lns_milp and lns_utils

function slope_scaling_cost_update!(timeSpaceGraph::TimeSpaceGraph, solution::Solution)
    for arc in edges(timeSpaceGraph.graph)
        arcData = timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        # Updating current cost
        timeSpaceGraph.currentCost[src(arc), dst(arc)] = arcData.unitCost
        # No scaling for linear arcs
        arcData.isLinear && continue
        # Total volume on arc
        arcBins = solution.bins[src(arc), dst(arc)]
        arcVolume = sum(bin.load for bin in arcBins; init=0)
        # No scaling for arcs with no volume
        arcVolume <= EPS && continue
        costFactor = length(arcBins) * arcData.capacity / arcVolume
        # Limiting cost factor to 2
        costFactor = min(2.0, costFactor)
        # Allowing cost decrease for common arcs
        if arcData.type in COMMON_ARC_TYPES
            costFactor -= 0.5
        end
        timeSpaceGraph.currentCost[src(arc), dst(arc)] *= costFactor
    end
end

# Adding variables

# TODO : store start nodes in TTGraph ?
function has_bundle_arc_var(
    TTGraph::TravelTimeGraph, src::Int, dst::Int, bundleStartNodes::Vector{Int}
)
    # IF it is a common arc, all bundles have variable
    !(TTGraph.networkArcs[src, dst].type in [:direct, :outsource, :shortcut]) && return true
    # If it is a start arc, only bundles starting at this arc have variable
    return src in bundleStartNodes
end

# TODO : add a mechanism to limit neighborhood size as a number of variables in the MILP ?

# Way too much varibale as most of them are unrelated to the bundle
function add_variables!(
    model::Model, neighborhood::Symbol, instance::Instance, startSol::RelaxedSolution
)
    TTGraph, timeSpaceGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    bundleIdxs = startSol.bundleIdxs
    bundles = instance.bundles[bundleIdxs]
    # Filtering useless variables to not create too much
    # TODO : sparse matrix of boolean would be more efficient ?
    bundleArcVar = [Int[] for _ in 1:length(instance.bundles)]
    for bundle in bundles
        # Getting all start nodes of the bundle
        startNodes = get_all_start_nodes(TTGraph, bundle)
        # Then iterating over all arcs 
        bundleArcVar[bundle.idx] = [
            a for (a, arc) in enumerate(edges(TTGraph.graph)) if
            has_bundle_arc_var(TTGraph, src(arc), dst(arc), startNodes)
        ]
    end
    # Variable x[b, a] in {0, 1} indicate if bundle b uses arc a in the travel time graph
    @variable(model, x[b in bundleIdxs, a in bundleArcVar[b]], Bin)
    if neighborhood == :attract || neighborhood == :reduce
        # Variable z[b] in {0, 1} indicate if bundle b uses old or new path
        @variable(model, z[startSol.bundleIdxs], Bin)
    end
    # Varible tau_a indicate the number of transport units used on arc a in the time space graph
    @variable(model, tau[arc in timeSpaceGraph.commonArcs], Int)
end

# Adding constraints

# TODO : think about the following
# Mis-using neighborhoods functions can lead to new neighborhoods
# If you can give any vector of bundles, than by slecting the bundles of a two shared node neighborhood and doing it the single plant way, we have another nieghborhood
# can be done by changing the nieghborhood name in the function called when doing the two shared node 

# Construct the matrix of right-hand side of paths constraints
function get_e_matrix(
    neighborhood::Symbol,
    bundleIdxs::Vector{Int},
    TTGraph::TravelTimeGraph,
    src::Int,
    dst::Int,
)
    I = repeat(bundleIdxs; outer=2)
    J = vcat(TTGraph.bundleSrc[bundleIdxs], TTGraph.bundleDst[bundleIdxs])
    V = vcat(-1 * ones(Int, length(bundleIdxs)), ones(Int, length(bundleIdxs)))
    if neighborhood == :two_shared_node
        if !has_vertex(TTGraph.graph, src) || !has_vertex(TTGraph.graph, dst)
            @warn "$neighborhood : src or dst is unknown. Switching to full paths for those bundles."
        else
            J = repeat([src, dst]; inner=length(bundleIdxs))
        end
    end
    return sparse(I, J, V, maximum(bundleIdxs), nv(TTGraph.graph))
end

# TODO : create more efficiently this, maybe with unique
# Creating a sparse matrix a expressions for the path constraints
function init_path_expr(model::Model, TTGraph::TravelTimeGraph, bundleIdxs::Vector{Int})
    B, V = Int[], Int[]
    sources = [src(arc) for arc in edges(TTGraph.graph)]
    dests = [dst(arc) for arc in edges(TTGraph.graph)]
    for varIdx in eachindex(model[:x])
        bunIdx, arcIdx = varIdx
        append!(B, [bunIdx, bunIdx])
        append!(V, [sources[arcIdx], dests[arcIdx]])
    end
    BB, VV, _ = findnz(sparse(B, V, [true for _ in 1:length(B)]))
    E = [AffExpr(0) for _ in 1:length(BB)]
    return sparse(BB, VV, E)
end

# TODO : check with the warning in get paths that the elementerity of paths is ok
# We may also create way too much path constraints, the same way we have too much x variables
# This is the major problem for now
# Add path constraints on the travel time graph to the model
function add_path_constraints!(
    model::Model,
    TTGraph::TravelTimeGraph,
    bundleIdxs::Vector{Int},
    e::SparseMatrixCSC{Int,Int},
)
    # TODO : those two lines have runtime dispatch
    sources = [src(arc) for arc in edges(TTGraph.graph)]
    dests = [dst(arc) for arc in edges(TTGraph.graph)]
    # Creating empty matrix of expressions
    pathConExpr = init_path_expr(model, TTGraph, bundleIdxs)
    # Iterating through model variables
    for varIdx in eachindex(model[:x])
        bunIdx, arcIdx = varIdx
        xVar = model[:x][bunIdx, arcIdx]
        # This tells us that var needs to be added in source arc constraint with -1 and dest arc constraint with +1   
        arcSrc = sources[arcIdx]
        add_to_expression!(pathConExpr[bunIdx, arcSrc], -1, xVar)
        arcDst = dests[arcIdx]
        add_to_expression!(pathConExpr[bunIdx, arcDst], 1, xVar)
    end
    # Efficient iteration over sparse matrices
    rows = rowvals(pathConExpr)
    # Whats happens if some node after the last one concerned by the path constraints is calles in the macro ?
    # TODO : change nv(TTGraph.graph) to size(pathConExpr, 2) because this is effectively the last node concerned
    @constraint(
        model,
        path[v in 1:size(pathConExpr, 2), b in rows[nzrange(pathConExpr, v)]],
        pathConExpr[b, v] == e[b, v]
    )
end

# TODO : test if changing to greedy insertion have better results

# Generate an attract path for arc src-dst and bundle
function generate_attract_path(
    instance::Instance,
    solution::Solution,
    bundle::Bundle,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int},
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Update cost matrix 
    update_lb_cost_matrix!(
        solution, TTGraph, TSGraph, bundle; use_bins=true, current_cost=true
    )
    # Compute path from bundleSrc to src and from dst to bundleDst
    bSrc, bDst = TTGraph.bundleSrc[bundle.idx], TTGraph.bundleDst[bundle.idx]
    # If bDst = dst then no path and that's problematic
    secondPart = if bDst == dst
        [bDst]
    else
        shortest_path(TTGraph, dst, bDst)[1]
    end
    return vcat(shortest_path(TTGraph, bSrc, src)[1], secondPart)
end

# Generate a reduce path for arc src-dst and bundle
function generate_reduce_path(
    instance::Instance,
    solution::Solution,
    bundle::Bundle,
    src::Int,
    dst::Int,
    CAPACITIES::Vector{Int},
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Update cost matrix 
    update_lb_cost_matrix!(
        solution, TTGraph, TSGraph, bundle; use_bins=true, current_cost=true
    )
    TTGraph.costMatrix[src, dst] = INFINITY
    # Compute path from bundleSrc to src and from dst to bundleDst
    bSrc, bDst = TTGraph.bundleSrc[bundle.idx], TTGraph.bundleDst[bundle.idx]
    return shortest_path(TTGraph, bSrc, bDst)[1]
end

# Generate new paths for the attract or reduce neighborhood
function generate_new_paths(
    neighborhood::Symbol,
    instance::Instance,
    solution::Solution,
    bundles::Vector{Bundle},
    src::Int,
    dst::Int,
)
    CAPACITIES = Int[]
    # If attract neighborhood and the edge is known
    if neighborhood == :attract
        if has_edge(instance.travelTimeGraph.graph, src, dst)
            return [
                generate_attract_path(instance, solution, bundle, src, dst, CAPACITIES) for
                bundle in bundles
            ]
        else
            @warn "$neighborhood : src-dst arc is unknown. Switching to reduce path generation."
        end
    end
    # Default case (chosen or not) is reduce
    return [
        generate_reduce_path(instance, solution, bundle, src, dst, CAPACITIES) for
        bundle in bundles
    ]
end

# TODO : store edge index in TTGraph ?
function create_edge_index(TTGraph::TravelTimeGraph)
    edgeIndex = zeros(Int, nv(TTGraph.graph), nv(TTGraph.graph))
    for (e, edge) in enumerate(edges(TTGraph.graph))
        edgeIndex[src(edge), dst(edge)] = e
    end
    return edgeIndex
end

# Adds equality constraints for the old and new path formulation
function add_old_new_path_constraints!(
    model::Model,
    bundles::Vector{Bundle},
    oldPaths::Vector{Vector{Int}},
    newPaths::Vector{Vector{Int}},
    edgeIndex::Matrix{Int},
)
    x, z = model[:x], model[:z]
    # Changing to sets due to some error 
    oldPathIndex = Set{Tuple{Int,Tuple{Int,Int}}}()
    newPathIndex, forceArcIndex = deepcopy(oldPathIndex), deepcopy(oldPathIndex)
    # oldPathIndex, newPathIndex = Tuple{Int,Tuple{Int,Int}}[], Tuple{Int,Tuple{Int,Int}}[]
    # forceArcIndex = Tuple{Int,Tuple{Int,Int}}[]
    for (bundle, oldPath, newPath) in zip(bundles, oldPaths, newPaths)
        # For every arc common in both paths, constraints will make it infeasible 
        oldArcs = collect(partition(oldPath, 2, 1))
        newArcs = collect(partition(newPath, 2, 1))
        commonArcs = intersect(oldArcs, newArcs)
        filter!(arc -> !(arc in commonArcs), oldArcs)
        filter!(arc -> !(arc in commonArcs), newArcs)
        # Adding arcs in each set
        for arc in oldArcs
            push!(oldPathIndex, (bundle.idx, arc))
        end
        for arc in newArcs
            push!(newPathIndex, (bundle.idx, arc))
        end
        for arc in commonArcs
            push!(forceArcIndex, (bundle.idx, arc))
        end
        # append!(oldPathIndex, [(bundle.idx, arc) for arc in oldArcs])
        # append!(newPathIndex, [(bundle.idx, arc) for arc in newArcs])
        # append!(forceArcIndex, [(bundle.idx, arc) for arc in commonArcs])
    end
    @constraint(
        model, oldPaths[(b, a) in oldPathIndex], 1 - z[b] == x[b, edgeIndex[a[1], a[2]]]
    )
    @constraint(
        model, newPaths[(b, a) in newPathIndex], z[b] == x[b, edgeIndex[a[1], a[2]]]
    )
    @constraint(model, forceArcs[(b, a) in forceArcIndex], x[b, edgeIndex[a[1], a[2]]] == 1)
end

# Initialize the packing expression as sparse matrix with space used and tau variables
function init_packing_expr(model::Model, TSGraph::TimeSpaceGraph, solution::Solution)
    I = [arc[1] for arc in TSGraph.commonArcs]
    J = [arc[2] for arc in TSGraph.commonArcs]
    # TODO : this line has runtime dispatch
    tau, bins, arcDatas = model[:tau], solution.bins, TSGraph.networkArcs
    E = [
        AffExpr(
            sum(bin.load for bin in bins[src, dst]; init=0),
            tau[(src, dst)] => -arcDatas[src, dst].capacity,
        ) for (src, dst) in TSGraph.commonArcs
    ]
    return sparse(I, J, E)
end

# Add path variables (after projection) with order volume coeffs to packing expressions 
function complete_packing_expr!(
    model::Model,
    expr::SparseMatrixCSC{AffExpr,Int},
    instance::Instance,
    bundles::Vector{Bundle},
    edgeIndex::Matrix{Int},
)
    x, TTGraph, TSGraph = model[:x], instance.travelTimeGraph, instance.timeSpaceGraph
    for bundle in bundles
        for order in bundle.orders, (src, dst) in TSGraph.commonArcs
            # Projecting back on the travel time graph
            ttSrc, ttDst = travel_time_projector(TTGraph, TSGraph, src, dst, order, bundle)
            # Checking the arc is for the bundle
            (ttSrc == -1 || ttDst == -1) && continue
            # Add the corresponding bundle variable and order volume to the expression
            add_to_expression!(
                expr[src, dst], x[bundle.idx, edgeIndex[ttSrc, ttDst]], order.volume
            )
        end
    end
end

# Add all relaxed packing constraints on shared arc of the time space graph
function add_packing_constraints!(
    model::Model,
    instance::Instance,
    bundles::Vector{Bundle},
    solution::Solution,
    edgeIndex::Matrix{Int},
)
    TSGraph = instance.timeSpaceGraph
    packing_expr = init_packing_expr(model, TSGraph, solution)
    complete_packing_expr!(model, packing_expr, instance, bundles, edgeIndex)
    @constraint(
        model, packing[(src, dst) in TSGraph.commonArcs], packing_expr[src, dst] <= 0
    )
end

# Add all constraints needed for the specified neighborhood
function add_constraints!(
    model::Model,
    neighborhood::Symbol,
    instance::Instance,
    solution::Solution,
    startSol::RelaxedSolution,
    src::Int=-1,
    dst::Int=-1,
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Path constraints on the travel time graph
    e = get_e_matrix(neighborhood, startSol.bundleIdxs, TTGraph, src, dst)
    add_path_constraints!(model, TTGraph, startSol.bundleIdxs, e)
    bundles = instance.bundles[startSol.bundleIdxs]
    edgeIndex = create_edge_index(TTGraph)
    if neighborhood == :attract || neighborhood == :reduce
        newPaths = generate_new_paths(neighborhood, instance, solution, bundles, src, dst)
        add_old_new_path_constraints!(
            model, bundles, startSol.bundlePaths, newPaths, edgeIndex
        )
    end
    # Relaxed packing constraint on the time space graph
    return add_packing_constraints!(model, instance, bundles, solution, edgeIndex)
end

# Constructing the objective

# TODO : loses a lot of time here
# Computes direct and outsource cost
function milp_travel_time_arc_cost(
    TTGraph::TravelTimeGraph, TSGraph::TimeSpaceGraph, bundles::Vector{Bundle}
)
    print("Creating MILP travel time arc costs... ")
    I, J, V = Int[], Int[], Float64[]
    # TODO : can be done by directly iterating on x
    # # TODO : store those vectors directly in the TTGraph
    # sources = [src(arc) for arc in edges(TTGraph.graph)]
    # dests = [dst(arc) for arc in edges(TTGraph.graph)]
    # for varIdx in eachindex(model[:x])
    #     bunIdx, arcIdx = varIdx
    #     push!(I, bunIdx)
    #     push!(J, arcIdx)
    #     arcSrc, arcDst = sources[arcIdx], dests[arcIdx]
    #     # No cost for shortcut arcs
    #     if TTGraph.networkArcs[arcSrc, arcDst].type == :shortcut
    #         push!(V, EPS)
    #         continue
    #     end
    # end
    for bundle in bundles
        # Getting all start nodes of the bundle
        startNodes = get_all_start_nodes(TTGraph, bundle)
        # Then iterating over all arcs 
        for (a, arc) in enumerate(edges(TTGraph.graph))
            # Filtering useless arcs
            !has_bundle_arc_var(TTGraph, src(arc), dst(arc), startNodes) && continue
            # Adding i and j to the matrix
            push!(I, bundle.idx)
            push!(J, a)
            # No cost for shortcut arcs
            if TTGraph.networkArcs[src(arc), dst(arc)].type == :shortcut
                push!(V, EPS)
                continue
            end
            # Common cost is the sum for orders of volume and stock cost
            arcCost = sum(
                volume_stock_cost(TTGraph, src(arc), dst(arc), order) for
                order in bundle.orders
            )
            # If it is a start arc, computing whole cost
            if src(arc) in startNodes
                for order in bundle.orders
                    timedSrc, timedDst = time_space_projector(
                        TTGraph, TSGraph, src(arc), dst(arc), order
                    )
                    arcData = TTGraph.networkArcs[src(arc), dst(arc)]
                    orderTrucks = get_transport_units(order, arcData)
                    arcCost += orderTrucks * TSGraph.currentCost[timedSrc, timedDst]
                end
            end
            push!(V, arcCost)
        end
    end
    println("done")
    return sparse(I, J, V, maximum(idx(bundles)), ne(TTGraph.graph))
end

# Sums the current cost of shared timed arcs and pre-computed surect and outsource arcs
function add_objective!(model::Model, instance::Instance, startSol::RelaxedSolution)
    x, tau = model[:x], model[:tau]
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    bundles = instance.bundles[startSol.bundleIdxs]
    x_cost = milp_travel_time_arc_cost(TTGraph, TSGraph, bundles)
    objExpr = AffExpr()
    for (src, dst) in TSGraph.commonArcs
        add_to_expression!(objExpr, tau[(src, dst)], TSGraph.currentCost[src, dst] / 100)
    end
    for varIdx in eachindex(x)
        bunIdx, arcIdx = varIdx
        add_to_expression!(objExpr, x[bunIdx, arcIdx], x_cost[bunIdx, arcIdx] / 100)
    end
    @objective(model, Min, objExpr)
end

# Shortcut arcs are missing from primal paths
function get_shortcut_part(TTGraph::TravelTimeGraph, bundleIdx::Int, startNode::Int)
    return collect(TTGraph.bundleSrc[bundleIdx]:-1:(startNode + 1))
end

# Warm start the milp with the current solution
# By default variables, not given are put to 0 which can render the warm start useless
function warm_start_milp!(
    model::Model,
    neighborhood::Symbol,
    instance::Instance,
    startSol::RelaxedSolution,
    edgeIndex::Matrix{Int},
)
    println("Warm starting MILP")
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    for (bundleIdx, bundlePath) in zip(startSol.bundleIdxs, startSol.bundlePaths)
        length(bundlePath) == 0 && continue
        # For tw_node neighborhood, no need to asjust with shortcut arcs
        completedPath = if neighborhood == :two_shared_node
            bundlePath
        else
            vcat(get_shortcut_part(TTGraph, bundleIdx, bundlePath[1]), bundlePath)
        end
        for (src, dst) in partition(completedPath, 2, 1)
            set_start_value(model[:x][bundleIdx, edgeIndex[src, dst]], 1)
        end
    end
    for (src, dst) in TSGraph.commonArcs
        arcCapacity = TSGraph.networkArcs[src, dst].capacity
        arcLoad = startSol.loads[src, dst]
        set_start_value(model[:tau][(src, dst)], ceil(arcLoad / arcCapacity))
    end
end

function warm_start_milp_test(model::Model, instance::Instance, startSol::RelaxedSolution)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    startValues = Dict{VariableRef,Float64}()
    for (bundleIdx, path) in zip(startSol.bundleIdxs, startSol.bundlePaths)
        completedPath = vcat(get_shortcut_part(TTGraph, bundleIdx, path[1]), path)
        println(completedPath)
        pathArcs = collect(partition(completedPath, 2, 1))
        println(pathArcs)
        for arc in edges(TTGraph.graph)
            arcKey = (src(arc), dst(arc))
            if arcKey in pathArcs
                startValues[model[:x][bundleIdx, arcKey]] = 1.0
            else
                startValues[model[:x][bundleIdx, arcKey]] = 0.0
            end
        end
    end
    for (src, dst) in TSGraph.commonArcs
        arcCapacity = TSGraph.networkArcs[src, dst].capacity
        arcLoad = startSol.loads[src, dst]
        startValues[model[:tau][(src, dst)]] = ceil(arcLoad / arcCapacity)
    end
    println("Start node in constraints : ")
    println(TTGraph.bundleSrc[startSol.bundleIdxs])
    println("Start paths : ")
    println(startSol.bundlePaths)
    println("Start values : ")
    println(startValues)
    infeasibility = primal_feasibility_report(model, startValues; skip_missing=true)
    println("Primal feasibility report :")
    return println(infeasibility)
end

# Getting the solution

function extract_arcs_from_vector(
    bundleArcVector::Vector{Float64}, TTGraph::TravelTimeGraph
)
    usedArcIdxs = findall(x -> x > EPS, bundleArcVector)
    # constructing list of edges
    return collect(edges(TTGraph.graph))[usedArcIdxs]
end

# Construct a path from a list of arcs
function get_path_from_arcs(
    bundle::Bundle, TTGraph::TravelTimeGraph, pathArcs::Vector{Edge{Int}}
)
    # constructing actual path
    # TODO : with two_shared_node neighborhood, no arc starting at bundleSrc !
    idxFirst = findfirst(a -> src(a) == TTGraph.bundleSrc[bundle.idx], pathArcs)
    lastNode = TTGraph.bundleDst[bundle.idx]
    # Quick fix for two_shared_node
    if isnothing(idxFirst)
        sources = [src(a) for a in pathArcs]
        dests = [dst(a) for a in pathArcs]
        # The first arc is the one with its source not in destinations (no arc goes to it)
        loneSrc = setdiff(sources, dests)[1]
        idxFirst = findfirst(a -> src(a) == loneSrc, pathArcs)
        # The opposite for the last node
        loneDst = setdiff(dests, sources)[1]
        lastNode = loneDst
    end
    path = [src(pathArcs[idxFirst]), dst(pathArcs[idxFirst])]
    # TODO : pop arcs from path arcs ?
    # some loop appeared in the path 
    try
        while path[end] != lastNode
            nextEdgeIdx = findfirst(a -> src(a) == path[end], pathArcs)
            nextEdge = popat!(pathArcs, nextEdgeIdx)
            push!(path, dst(nextEdge))
        end
    catch e
        println("bundle : $bundle")
        println(
            "bundle src and dst : $(TTGraph.bundleSrc[bundle.idx]), $(TTGraph.bundleDst[bundle.idx])",
        )
        println("path arcs : $pathArcs")
        println("idx first : $idxFirst")
        println("first edge : $(pathArcs[idxFirst])")
        println("last node : $lastNode")
        println("start of path : $(path[1:20])")
        println("length path : $(length(path))")
    end
    remove_shortcuts!(path, TTGraph)
    return path
end

# TODO : Elementarity cinstraint could be sum of incoming x arc var of the problematic nodes to be less than one

# TODO : a lot of runtime dispatch in here
function get_paths(model::Model, instance::Instance, startSol::RelaxedSolution)
    TTGraph = instance.travelTimeGraph
    bundles = instance.bundles[startSol.bundleIdxs]
    # getting x variable value
    xValue = value.(model[:x])
    paths = Vector{Vector{Int}}()
    allArcs = collect(edges(TTGraph.graph))
    for bundle in bundles
        # finding the non zero values to indicate edges used
        xBundleValue = xValue[bundle.idx, :]
        usedArcs = [
            allArcs[arcIdx] for
            (arcIdx,) in eachindex(xBundleValue) if xBundleValue[arcIdx] > EPS
        ]
        bundlePath = get_path_from_arcs(bundle, TTGraph, usedArcs)
        # TODO : attract paths may result in non admissible paths
        # !is_path_admissible(TTGraph, bundlePath) &&
        #     @warn "Path proposed with milp is not admissible, add elementarity constraint !" :bundle =
        #         bundle :path = join(bundlePath, "-") :nodes = join(
        #         string.(map(n -> TTGraph.networkNodes[n], bundlePath)), ", "
        #     )
        push!(paths, bundlePath)
    end
    return paths
end

# Selecting a plant or a common arc
# TODO : store plants and common arcs in TTGraph ?

function select_random_plant(instance::Instance)
    TTGraph = instance.travelTimeGraph
    return rand(findall(node -> node.type == :plant, TTGraph.networkNodes))
end

# TODO : stack bundles associated with plants until the cost threshold is reached ?
function select_random_plant(instance::Instance, solution::Solution, costThreshold::Float64)
    src, dst, allPertBunIdxs, estimRemCost = -1, -1, Int[], 0.0
    TTGraph = instance.travelTimeGraph
    plants = findall(node -> node.type == :plant, TTGraph.networkNodes)
    # Going through all plants in random order to select one
    for plant in shuffle(plants)
        pertBunIdxs = get_bundles_to_update(instance, solution, plant)
        # If no bundle for this plant, skipping to another directly
        length(pertBunIdxs) == 0 && continue
        # Computing estimated cost
        pertBundles = instance.bundles[pertBunIdxs]
        oldPaths = get_lns_paths_to_update(:single_plant, solution, pertBundles, src, dst)
        estimRemCost += sum(
            bundle_estimated_removal_cost(bundle, oldPath, instance, solution) for
            (bundle, oldPath) in zip(pertBundles, oldPaths)
        )
        # Adding bundles to the list of perturbed bundles
        append!(allPertBunIdxs, pertBunIdxs)
        # If it is suitable, breaking search and returning
        estimRemCost > costThreshold && return src, dst, allPertBunIdxs
    end
    # If no plant found, returning empty vector
    return src, dst, Int[]
end

function select_common_arc(instance::Instance)
    TTGraph = instance.travelTimeGraph
    arc = rand(
        filter(
            arc -> TTGraph.networkArcs[src(arc), dst(arc)].type in COMMON_ARC_TYPES,
            collect(edges(TTGraph.graph)),
        ),
    )
    return src(arc), dst(arc)
end

# TODO : also stacking bundles for those ?
function select_random_common_arc(
    neighborhood::Symbol, instance::Instance, solution::Solution, costThreshold::Float64
)
    arcSrc, arcDst, pertBunIdxs, estimRemCost = -1, -1, Int[], 0.0
    TTGraph = instance.travelTimeGraph
    commonArcs = filter(
        arc -> TTGraph.networkArcs[src(arc), dst(arc)].type in COMMON_ARC_TYPES,
        collect(edges(TTGraph.graph)),
    )
    # Going through all common arcs in random order to select one
    for arc in shuffle(commonArcs)
        pertBunIdxs = get_bundles_to_update(instance, solution, src(arc), dst(arc))
        if neighborhood == :attract
            pertBunIdxs = findall(
                bun -> is_bundle_attract_candidate(
                    bun, pertBunIdxs, TTGraph, src(arc), dst(arc)
                ),
                instance.bundles,
            )
        end
        # If no bundle for this common arc, skipping to another directly
        length(pertBunIdxs) == 0 && continue
        # Computing estimated cost
        pertBundles = instance.bundles[pertBunIdxs]
        oldPaths = get_lns_paths_to_update(
            :attract, solution, pertBundles, src(arc), dst(arc)
        )
        estimRemCost = sum(
            bundle_estimated_removal_cost(bundle, oldPath, instance, solution) for
            (bundle, oldPath) in zip(pertBundles, oldPaths)
        )
        # If it is suitable, breaking search and returning
        estimRemCost > costThreshold && return src(arc), dst(arc), pertBunIdxs
    end
    # If no common arc found, returning empty vector
    return arcSrc, arcDst, Int[]
end

function is_bundle_attract_candidate(
    bundle::Bundle, pertBunIdxs::Vector{Int}, TTGraph::TravelTimeGraph, src::Int, dst::Int
)
    return !(bundle.idx in pertBunIdxs) &&
           has_path(TTGraph.graph, TTGraph.bundleSrc[bundle.idx], src) &&
           has_path(TTGraph.graph, dst, TTGraph.bundleDst[bundle.idx])
end

function select_random_two_node(
    instance::Instance, solution::Solution, costThreshold::Float64
)
    src, dst, pertBunIdxs, estimRemCost = -1, -1, Int[], 0.0
    TTGraph = instance.travelTimeGraph
    plantNodes = findall(x -> x.type == :plant, TTGraph.networkNodes)
    two_node_nodes = vcat(TTGraph.commonNodes, plantNodes)
    for src in shuffle(two_node_nodes), dst in shuffle(two_node_nodes)
        # If nodes are not candidate, skipping
        !are_nodes_candidate(TTGraph, src, dst) && continue
        pertBunIdxs = get_bundles_to_update(instance, solution, src, dst)
        # If no bundle for these two nodes, skipping to another directly
        length(pertBunIdxs) == 0 && continue
        # Computing estimated cost
        pertBundles = instance.bundles[pertBunIdxs]
        oldPaths = get_lns_paths_to_update(
            :two_shared_node, solution, pertBundles, src, dst
        )
        estimRemCost = sum(
            bundle_estimated_removal_cost(bundle, oldPath, instance, solution) for
            (bundle, oldPath) in zip(pertBundles, oldPaths)
        )
        # If it is suitable, breaking search and returning
        estimRemCost > costThreshold && return src, dst, pertBunIdxs
    end
    # If no two nodes found, returning empty vector
    return src, dst, Int[]
end

function select_random_suppliers(
    instance::Instance, solution::Solution, costThreshold::Float64
)
    src, dst, allPertBunIdxs, estimRemCost = -1, -1, Int[], 0.0
    TTGraph = instance.travelTimeGraph
    suppliers = findall(node -> node.type == :supplier, TTGraph.networkNodes)
    # Going through all plants in random order to select one
    for supplier in shuffle(suppliers)
        pertBunIdxs = findall(bunSrc -> bunSrc == supplier, TTGraph.bundleSrc)
        # If no bundle for this plant, skipping to another directly
        length(pertBunIdxs) == 0 && continue
        # Computing estimated cost
        pertBundles = instance.bundles[pertBunIdxs]
        oldPaths = get_lns_paths_to_update(:single_plant, solution, pertBundles, src, dst)
        estimRemCost += sum(
            bundle_estimated_removal_cost(bundle, oldPath, instance, solution) for
            (bundle, oldPath) in zip(pertBundles, oldPaths)
        )
        # Adding bundles to the list of perturbed bundles
        append!(allPertBunIdxs, pertBunIdxs)
        # If it is suitable, breaking search and returning
        estimRemCost > costThreshold && return src, dst, allPertBunIdxs
    end
    # If no suppliers found, returning empty vector
    return src, dst, Int[]
end

function select_random_bundles(
    instance::Instance, solution::Solution, costThreshold::Float64
)
    src, dst, allPertBunIdxs, estimRemCost = -1, -1, Int[], 0.0
    TTGraph = instance.travelTimeGraph
    shuffledBundles = randperm(length(instance.bundles))
    # Going through all bundles in random order to select one
    for i in 10:100
        nBundles = round(Int, i / 100 * length(instance.bundles))
        pertBunIdxs = shuffledBundles[1:nBundles]
        # Computing estimated cost
        pertBundles = instance.bundles[pertBunIdxs]
        oldPaths = get_lns_paths_to_update(:single_plant, solution, pertBundles, src, dst)
        estimRemCost += sum(
            bundle_estimated_removal_cost(bundle, oldPath, instance, solution) for
            (bundle, oldPath) in zip(pertBundles, oldPaths)
        )
        # Adding bundles to the list of perturbed bundles
        allPertBunIdxs = pertBunIdxs
        # If it is suitable, breaking search and returning
        estimRemCost > costThreshold && return src, dst, allPertBunIdxs
    end
    # If no plant found, returning empty vector
    return src, dst, Int[]
end

function get_neighborhood_node_and_bundles(
    neighborhood::Symbol, instance::Instance, solution::Solution
)::Tuple{Int,Int,Vector{Int}}
    src, dst, pertBunIdxs = -1, -1, Int[]
    if neighborhood == :single_plant
        while length(pertBunIdxs) == 0
            pertBunIdxs = get_bundles_to_update(
                instance, solution, select_random_plant(instance)
            )
        end
    elseif neighborhood == :two_shared_node
        while length(pertBunIdxs) == 0
            src, dst = select_two_nodes(instance.travelTimeGraph)
            pertBunIdxs = get_bundles_to_update(instance, solution, src, dst)
        end
    else
        while length(pertBunIdxs) == 0
            src, dst = select_common_arc(instance)
            # If reduce, than bundles on the arc
            pertBunIdxs = get_bundles_to_update(instance, solution, src, dst)
            # If attract, other bundles
            if neighborhood == :attract
                # TODO : this can still make a awful lot of bundles, to test 
                # Attract only on maritime arcs and stepToDel = 0 dst ?
                TTGraph = instance.travelTimeGraph
                pertBunIdxs = findall(
                    bun -> is_bundle_attract_candidate(bun, pertBunIdxs, TTGraph, src, dst),
                    instance.bundles,
                )
            end
        end
    end
    return src, dst, pertBunIdxs
end

function get_lns_paths_to_update(
    neighborhood::Symbol,
    solution::Solution,
    bundles::Vector{Bundle},
    node1::Int,
    node2::Int,
)::Vector{Vector{Int}}
    if neighborhood == :two_shared_node && node1 != -1 && node2 != -1
        return get_paths_to_update(solution, bundles, node1, node2)
    else
        return solution.bundlePaths[idx(bundles)]
    end
end

#######################################################################################
# New idea to be tested
#######################################################################################

# The neighborhood only determines the bundles concerned and the potential paths for them
# Doesn't work for two node for now because need to put src and dst as arguments
# Works for single_plant, random, suppliers, attract and reduce
# POC for now

function generate_bundle_potential_paths(
    instance::Instance, solution::Solution, bundle::Bundle; nPaths::Int
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Update cost matrix 
    update_lb_cost_matrix!(solution, TTGraph, TSGraph, bundle; use_bins=false)
    # Compute n paths from bundleSrc to bundleDst
    # TODO : with this setting, as all paths are independent, this generation can be done once at the beginning
    # Even without this setting it could be done once at the beginning and updated once in a while
    bSrc, bDst = TTGraph.bundleSrc[bundle.idx], TTGraph.bundleDst[bundle.idx]
    yenState = yen_k_shortest_paths(
        travelTimeGraph.graph, src, travelTimeGraph.costMatrix, nPaths; maxdist=INFINITY
    )
    # TODO : maybe the k shortest path generation will be the bottleneck
    # Keeping shortcuts or ease of MILP implementation
    return enumerate_paths(yenState)
end

function add_variables_paths!(
    model::Model, instance::Instance, startSol::RelaxedSolution, nPaths::Int
)
    TSGraph = instance.timeSpaceGraph
    bundleIdxs = startSol.bundleIdxs
    # Variable p[b, k] in {0, 1} indicate if bundle b uses path k in the travel time graph
    @variable(model, p[b in bundleIdxs, k in 1:nPaths], Bin)
    # Varible tau_a indicate the number of transport units used on arc a in the time space graph
    @variable(model, tau[arc in timeSpaceGraph.commonArcs], Int)
end

function add_path_constraints_paths!(model::Model, bundleIdxs::Vector{Int})
    p = model[:p]
    # 1 path needs to be chosen between all potential paths
    @constraint(model, paths[b in bundleIdxs], sum(p[b, :]) == 1)
end

function complete_packing_expr_paths!(
    model::Model,
    expr::SparseMatrixCSC{AffExpr,Int},
    instance::Instance,
    bundles::Vector{Bundle},
    potentialPaths::Vector{Vector{Vector{Int}}},
)
    p, TTGraph, TSGraph = model[:p], instance.travelTimeGraph, instance.timeSpaceGraph
    # Iterating each potential paths of each bundle
    for bundle in bundles
        for bundlePaths in potentialPaths[bundle.idx]
            # For each potential path
            for (k, path) in bundlePaths
                # For each arc of this potential bundle path
                for (src, dst) in partition(path, 2, 1)
                    # If it is not a common arc, filtering 
                    !TTGraph.networkArcs[src, dst].isCommon && continue
                    # Projecting arc on the time space graph for each order of the bundle
                    for order in bundle.orders
                        tSrc, tDst = time_space_projector(TTGraph, TSGraph, src, dst, order)
                        # Adding the corresponding variable to the packing constraint
                        add_to_expression!(expr[tSrc, tDst], p[bundle.idx, k], order.volume)
                    end
                end
            end
        end
    end
end

# Add all relaxed packing constraints on shared arc of the time space graph
function add_packing_constraints_paths!(
    model::Model,
    instance::Instance,
    bundles::Vector{Bundle},
    solution::Solution,
    potentialPaths::Vector{Vector{Vector{Int}}},
)
    TSGraph = instance.timeSpaceGraph
    packing_expr = init_packing_expr(model, TSGraph, solution)
    complete_packing_expr_paths!(model, packing_expr, instance, bundles, potentialPaths)
    @constraint(
        model, packing[(src, dst) in TSGraph.commonArcs], packing_expr[src, dst] <= 0
    )
end

function add_constraints_paths!(
    model::Model,
    instance::Instance,
    solution::Solution,
    startSol::RelaxedSolution,
    potentialPaths::Vector{Vector{Vector{Int}}},
)
    # Path constraints on the travel time graph
    add_path_constraints_paths!(model, startSol.bundleIdxs)
    bundles = instance.bundles[startSol.bundleIdxs]
    # Relaxed packing constraint on the time space graph
    return add_packing_constraints_paths!(
        model, instance, bundles, solution, potentialPaths
    )
end

# TODO : base costs can also be precomputed once at the beginning
function milp_travel_time_path_cost(
    TTGraph::TravelTimeGraph,
    TSGraph::TimeSpaceGraph,
    bundles::Vector{Bundle},
    potentialPaths::Vector{Vector{Vector{Int}}},
)
    print("Creating MILP potential paths costs... ")
    nBun, nPaths = length(potentialPaths), length(potentialPaths[1])
    potentialCosts = [zeros(nPaths) for _ in 1:nBun]
    for bundle in bundles
        for bundlePaths in potentialPaths[bundle.idx]
            for (k, path) in bundlePaths
                pathCost = 0.0
                for (src, dst) in partition(path, 2, 1)
                    arcData = TTGraph.networkArcs[src, dst]
                    # No cost for shortcut arcs
                    if arcData.type == :shortcut
                        pathCost += 1e-5
                        continue
                    end
                    # Common cost is the sum for orders of volume and stock cost
                    pathCost += sum(
                        volume_stock_cost(TTGraph, src, dst, order) for
                        order in bundle.orders
                    )
                    # Complete cost for outsource and direct arcs
                    if arcData.type in [:outsource, :direct]
                        for order in bundle.orders
                            tSrc, tDst = time_space_projector(
                                TTGraph, TSGraph, src, dst, order
                            )
                            orderTrucks = get_lb_transport_units(order, arcData)
                            pathCost +=
                                orderTrucks * TSGraph.currentCost[timedSrc, timedDst]
                        end
                    end
                end
                potentialCosts[bundle.idx][k] = pathCost
            end
        end
    end
    println("done")
    return potentialCosts
end

# Sums the current cost of shared timed arcs and pre-computed surect and outsource arcs
function add_objective_paths!(
    model::Model,
    instance::Instance,
    startSol::RelaxedSolution,
    potentialPaths::Vector{Vector{Vector{Int}}},
)
    p, tau = model[:p], model[:tau]
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    bundles = instance.bundles[startSol.bundleIdxs]
    p_cost = milp_travel_time_path_cost(TTGraph, TSGraph, bundles, potentialPaths)
    objExpr = AffExpr()
    for (src, dst) in TSGraph.commonArcs
        add_to_expression!(objExpr, tau[(src, dst)], TSGraph.currentCost[src, dst])
    end
    for varIdx in eachindex(p)
        bunIdx, pathIdx = varIdx
        add_to_expression!(objExpr, p[bunIdx, pathIdx], p_cost[bunIdx][pathIdx])
    end
    @objective(model, Min, objExpr)
end

function get_paths_paths(
    model::Model,
    instance::Instance,
    startSol::RelaxedSolution,
    potentialPaths::Vector{Vector{Vector{Int}}},
)
    TTGraph = instance.travelTimeGraph
    bundles = instance.bundles[startSol.bundleIdxs]
    # getting x variable value
    pValue = value.(model[:p])
    paths = Vector{Vector{Int}}()
    allArcs = collect(edges(TTGraph.graph))
    for bundle in bundles
        # finding the non zero value to indicate path used
        pBundleValue = pvalue[bundle.idx, :]
        usedPathIdx = findfirst(x -> x > 1 - 1e-3, pBundleValue)
        bundlePath = potentialPaths[bundle.idx][usedPathIdx]
        !is_path_admissible(TTGraph, bundlePath) &&
            @warn "Path proposed with milp is not admissible, add elementarity constraint !" :bundle =
                bundle :path = join(bundlePath, "-") :nodes = join(
                string.(map(n -> TTGraph.networkNodes[n], bundlePath)), ", "
            )
        push!(paths, bundlePath)
    end
    return paths
end

# bundle, arc, and so on selection unction don't need to be changed
