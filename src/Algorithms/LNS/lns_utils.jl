# Utils function for the large neighborhood search

# For arcs in the time-space network :
#     Update the current cost with the following mechanism :
#         Compute an actual volume cost : volume_cost = (unit_cost * nb_of_units) / total_volume_in_units
#         Compute the updated unit cost : unit cost = unit_capacity * volume_cost
# Use this new costs in all the other heuristics

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
        timeSpaceGraph.currentCost[src(arc), dst(arc)] *= costFactor
    end
end

# Adding variables

function add_variables!(
    model::Model, neighborhood::Symbol, instance::Instance, startSol::RelaxedSolution
)
    travelTimeGraph, timeSpaceGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    bundleIdxs = startSol.bundleIdxs
    # Variable x[b, a] in {0, 1} indicate if bundle b uses arc a in the travel time graph
    arcs = [(src(arc), dst(arc)) for arc in edges(travelTimeGraph.graph)]
    @variable(model, x[bundleIdxs, arcs], Bin)
    if neighborhood == :attract || neighborhood == :reduce
        # Variable z[b] in {0, 1} indicate if bundle b uses old or new path
        @variable(model, z[bundleIdxs], Bin)
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
    return sparse(I, J, V)
end

# TODO : check with the warning in get paths that the elementerity of paths is ok
# Add path constraints on the travel time graph to the model
function add_path_constraints!(
    model::Model,
    TTGraph::TravelTimeGraph,
    bundleIdxs::Vector{Int},
    e::SparseMatrixCSC{Int,Int},
)
    incMatrix, x = incidence_matrix(TTGraph.graph), model[:x]
    # Is the incicdence matrix constructed by iterating the same way as edges ? Seems yes from the documentation
    @constraint(
        model,
        path[b in bundleIdxs],
        sum(
            incMatrix[:, a] * x[b, (src(arc), dst(arc))] for
            (a, arc) in enumerate(edges(TTGraph.graph))
        ) .== e[b, :]
    )
end

# Generate an attract path for arc src-dst and bundle
function generate_attract_path(
    instance::Instance, solution::Solution, bundle::Bundle, src::Int, dst::Int
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Update cost matrix 
    update_lb_cost_matrix!(solution, TTGraph, TSGraph, bundle; giant=true)
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
    instance::Instance, solution::Solution, bundle::Bundle, src::Int, dst::Int
)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    # Update cost matrix 
    update_lb_cost_matrix!(solution, TTGraph, TSGraph, bundle; giant=true)
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
    # If attract neighborhood and the edge is known
    if neighborhood == :attract
        if has_edge(instance.travelTimeGraph.graph, src, dst)
            return [
                generate_attract_path(instance, solution, bundle, src, dst) for
                bundle in bundles
            ]
        else
            @warn "$neighborhood : src-dst arc is unknown. Switching to reduce path generation."
        end
    end
    # Default case (chosen or not) is reduce
    return [
        generate_reduce_path(instance, solution, bundle, src, dst) for bundle in bundles
    ]
end

# Adds equality constraints for the old and new path formulation
function add_old_new_path_constraints!(
    model::Model,
    bundles::Vector{Bundle},
    oldPaths::Vector{Vector{Int}},
    newPaths::Vector{Vector{Int}},
)
    x, z = model[:x], model[:z]
    oldPathIndex, newPathIndex = Tuple{Int,Tuple{Int,Int}}[], Tuple{Int,Tuple{Int,Int}}[]
    for (bundle, oldPath, newPath) in zip(bundles, oldPaths, newPaths)
        append!(oldPathIndex, [(bundle.idx, arc) for arc in partition(oldPath, 2, 1)])
        # If old path = new path, constraints makes model infeasible
        # Adding only one of them imposes that the common path is taken
        if oldPath != newPath
            append!(newPathIndex, [(bundle.idx, arc) for arc in partition(newPath, 2, 1)])
        end
    end
    @constraint(model, oldPaths[(b, a) in oldPathIndex], 1 - z[b] == x[b, a])
    @constraint(model, newPaths[(b, a) in newPathIndex], z[b] == x[b, a])
end

# Initialize the packing expression as sparse matrix with space used and tau variables
function init_packing_expr(model::Model, TSGraph::TimeSpaceGraph, solution::Solution)
    I = [arc[1] for arc in TSGraph.commonArcs]
    J = [arc[2] for arc in TSGraph.commonArcs]
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
)
    x, TTGraph, TSGraph = model[:x], instance.travelTimeGraph, instance.timeSpaceGraph
    for bundle in bundles
        for order in bundle.orders, (src, dst) in TSGraph.commonArcs
            # Projecting back on the travel time graph
            ttSrc, ttDst = travel_time_projector(TTGraph, TSGraph, src, dst, order, bundle)
            # Checking the arc is for the bundle
            (ttSrc == -1 || ttDst == -1) && continue
            # Add the corresponding bundle variable and order volume to the expression
            add_to_expression!(expr[src, dst], x[bundle.idx, (ttSrc, ttDst)], order.volume)
        end
    end
end

# Add all relaxed packing constraints on shared arc of the time space graph
function add_packing_constraints!(
    model::Model, instance::Instance, bundles::Vector{Bundle}, solution::Solution
)
    TSGraph = instance.timeSpaceGraph
    packing_expr = init_packing_expr(model, TSGraph, solution)
    complete_packing_expr!(model, packing_expr, instance, bundles)
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
    if neighborhood == :attract || neighborhood == :reduce
        println("Neighborhood : $(neighborhood)")
        println("Start paths : $(startSol.bundlePaths)")
        newPaths = generate_new_paths(neighborhood, instance, solution, bundles, src, dst)
        println("Proposed paths : $(newPaths)")
        add_old_new_path_constraints!(model, bundles, startSol.bundlePaths, newPaths)
    end
    # Relaxed packing constraint on the time space graph
    return add_packing_constraints!(model, instance, bundles, solution)
end

# Constructing the objective

# TODO : for all x variables, I am missing valume stock cost and carbon cost !

function has_arc_milp_cost(
    TTGraph::TravelTimeGraph, src::Int, dst::Int, startNodes::Vector{Int}
)
    return !(TTGraph.networkArcs[src, dst].type in [:direct, :outsource, :shortcut]) ||
           src in startNodes
end

# Computes direct and outsource cost
function milp_travel_time_arc_cost(
    TTGraph::TravelTimeGraph, TSGraph::TimeSpaceGraph, bundles::Vector{Bundle}
)
    I, J, V = Int[], Int[], Float64[]
    for bundle in bundles
        # Getting all start nodes of the bundle
        startNodes = get_all_start_nodes(TTGraph, bundle)
        # Then iterating over all arcs 
        for (a, arc) in enumerate(edges(TTGraph.graph))
            # Filtering useless arcs
            !has_arc_milp_cost(TTGraph, src(arc), dst(arc), startNodes) && continue
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
                    orderTrucks = get_lb_transport_units(order, arcData)
                    arcCost += orderTrucks * TSGraph.currentCost[timedSrc, timedDst]
                end
            end
            push!(V, arcCost)
        end
    end
    # Adding Eps value at the bottom right corner to get a matrix with the correct size
    push!(I, maximum(idx(bundles)))
    push!(J, ne(TTGraph.graph))
    push!(V, EPS)
    return sparse(I, J, V)
end

# Sums the current cost of shared timed arcs and pre-computed surect and outsource arcs
function add_objective!(model::Model, instance::Instance, startSol::RelaxedSolution)
    x, tau = model[:x], model[:tau]
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    bundles = instance.bundles[startSol.bundleIdxs]
    x_cost = milp_travel_time_arc_cost(TTGraph, TSGraph, bundles)
    objExpr = AffExpr()
    for (src, dst) in TSGraph.commonArcs
        add_to_expression!(objExpr, tau[(src, dst)], TSGraph.currentCost[src, dst])
    end
    for (a, arc) in enumerate(edges(TTGraph.graph))
        arcKey = (src(arc), dst(arc))
        for bundle in bundles
            add_to_expression!(objExpr, x[bundle.idx, arcKey], x_cost[bundle.idx, a])
        end
    end
    @objective(model, Min, objExpr)
end

# Shortcut arcs are missing from primal paths
function get_shortcut_part(TTGraph::TravelTimeGraph, bundleIdx::Int, startNode::Int)
    return collect(TTGraph.bundleSrc[bundleIdx]:-1:(startNode + 1))
end

# Warm start the milp with the current solution
# By default variables, not given are put to 0 which can render the warm start useless
function warm_start_milp!(model::Model, instance::Instance, startSol::RelaxedSolution)
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    for (bundleIdx, bundlePath) in zip(startSol.bundleIdxs, startSol.bundlePaths)
        length(bundlePath) == 0 && continue
        completedPath = vcat(
            get_shortcut_part(TTGraph, bundleIdx, bundlePath[1]), bundlePath
        )
        for (src, dst) in partition(completedPath, 2, 1)
            set_start_value(model[:x][bundleIdx, (src, dst)], 1)
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
    idxFirst = findfirst(a -> src(a) == TTGraph.bundleSrc[bundle.idx], pathArcs)
    path = [src(pathArcs[idxFirst]), dst(pathArcs[idxFirst])]
    while path[end] != TTGraph.bundleDst[bundle.idx]
        nextEdge = findfirst(a -> src(a) == path[end], pathArcs)
        push!(path, dst(pathArcs[nextEdge]))
    end
    remove_shortcuts!(path, TTGraph)
    return path
end

function get_paths(model::Model, instance::Instance, startSol::RelaxedSolution)
    TTGraph = instance.travelTimeGraph
    bundles = instance.bundles[startSol.bundleIdxs]
    # getting x variable value
    xValue = value.(model[:x])
    paths = Vector{Vector{Int}}()
    for bundle in bundles
        # finding the non zero values to indicate edges used
        xBundleValue = xValue[bundle.idx, :]
        bundleArcVector = [xBundleValue[key] for key in keys(xBundleValue)]
        usedArcs = extract_arcs_from_vector(bundleArcVector, TTGraph)
        bundlePath = get_path_from_arcs(bundle, TTGraph, usedArcs)
        !is_path_admissible(TTGraph, bundlePath) &&
            @warn "Path proposed with milp is not admissible, add elementarity constraint !" :bundle =
                bundle :path = bundlePath
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

function is_bundle_attract_candidate(
    bundle::Bundle, pertBunIdxs::Vector{Int}, TTGraph::TravelTimeGraph, src::Int, dst::Int
)
    return !(bundle.idx in pertBunIdxs) &&
           has_path(TTGraph.graph, TTGraph.bundleSrc[bundle.idx], src) &&
           has_path(TTGraph.graph, dst, TTGraph.bundleDst[bundle.idx])
end

function get_neighborhood_node_and_bundles(
    neighborhood::Symbol, instance::Instance, solution::Solution
)
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
)
    if neighborhood == :two_node && node1 != -1 && node2 != -1
        return get_paths_to_update(solution, bundles, node1, node2)
    else
        return solution.bundlePaths[idx(bundles)]
    end
end
