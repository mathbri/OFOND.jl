# Copy of the Dijkstra shortest path implementation
# The only difference resides in the memory management

# TODO : next step would be to have a pre-allocated vector for the result 

# TODO : test this function against the one in Graphs.jl

function initialize_dijkstra!(
    g::SimpleDiGraph,
    dists::Vector{Float64},
    parents::Vector{Int},
    queue::PriorityQueue{Int,Float64},
)
    # Do all the initializing of objects here
    nvg = nv(g)
    # dists = fill(typemax(T), nvg)
    fill!(dists, INFINITY)
    if length(dists) < nvg
        append!(dists, fill(INFINITY, nvg - length(dists)))
    end
    # parents = zeros(U, nvg)
    fill!(parents, 0)
    if length(parents) < nvg
        append!(parents, fill(0, nvg - length(parents)))
    end
    # H = PriorityQueue{U,T}()
    return empty!(queue)
end

# Copy of Dijkstra's implementation 
# Specialized for the travel time graph 
# Returning directly the path as a vector of nodes
# Structure used as argument for memory management purposes
function my_dijkstra(
    g::SimpleDiGraph,
    src::Int,
    dst::Int,
    distmx::Matrix{Float64};
    dists::Vector{Float64},
    parents::Vector{Int},
    queue::PriorityQueue{Int,Float64},
)
    # No path if src == dst
    if src == dst
        return Int[]
    end
    # Initialize objects
    initialize_dijkstra!(g, dists, parents, queue)
    # Inserting the source in the priority queue
    dists[src] = 0
    queue[src] = 0
    # Iterating the queue
    while !isempty(queue)
        u = dequeue!(queue)
        # If we dequeue dst, then the shortest path is found
        u == dst && break
        # Shortest path distance from src to u
        d = dists[u]
        for v in outneighbors(g, u)
            # Path distance from src to v if we go through u
            alt = d + distmx[u, v]
            # Distance > INFINITY means that there is no path or u-v is a forbidden arc
            alt > INFINITY && continue
            # If we found a shorter path, we update distance, parents, and altitude in queue
            if alt < dists[v]
                dists[v] = alt
                parents[v] = u
                queue[v] = alt
            end
        end
    end
    # No path if dists[dst] has stayed to infinity
    if dists[dst] ≈ INFINITY
        return Int[]
    end
    # No parent for the source
    parents[src] = 0
    # Path is then computed directly without using DijkstraState
    path = [dst]
    while path[1] != src
        insert!(path, 1, parents[path[end]])
    end
    return path, dists[dst]
end

# TODO : La dominanace se fait par rapport aux ressources qui sont utilisés
# - un chemin plus long qui n'utilise pas les mêmes ressources ne peut être coupés

# Implementation of the ressource constrained shortest path a star specialized to our problem
function my_ressource_a_star(
    g::SimpleDiGraph,
    src::Int,
    dst::Int,
    distmx::Matrix{Float64},
    nodesData::Vector{NetworkNode};
    dists::Vector{Float64},
    parents::Vector{Int},
    queue::PriorityQueue{Int,Float64},
    verbose::Bool=false,
)
    # No path if src == dst
    if src == dst
        return Int[]
    end
    # Computing bounds by reverse dijkstra without ressource constraints
    rg, tdistmx = reverse(g), transpose(distmx)
    my_dijkstra(rg, dst, src, tdistmx; dists=dists, parents=parents, queue=queue)
    bounds = deepcopy(dists)
    # Computing shortest path with explicit elementarity constraint
    dists[src] = 0
    resources = Dict{Vector{Int},Vector{UInt}}([src] => UInt[])
    L = PriorityQueue{Vector{Int},Float64}([src] => 0.0)
    # Initialization
    c_star = Inf
    p_star = [src]
    while !isempty(L)
        # Dequeing path with smallest cost
        p, cp = popfirst!(L)
        v = p[end]
        rp = resources[p]
        for w in outneighbors(graph, v)
            # Checking path extension admissibility 
            wHash = nodesData[w].hash
            if wHash in rp
                continue
            end
            # Extanding path and ressource with neighbor
            q = copy(p)
            push!(q, w)
            if nodesData[w].type != :supplier
                # Multiple supplier is possible because of shortcut arcs
                rq = copy(rp)
                push!(rq, wHash)
            end
            # Computing new cost 
            cq = cp + distmx[v, w]
            # Storing best sol
            if w == dst && cq < c_star
                c_star = cq
                p_star = copy(q)
                continue
            end
            altq = cq + bounds[w]
            # Adding it to the queue
            if altq < c_star
                resources[q] = rq
                push!(L, q => altq)
            end
        end
    end
    return p_star, c_star
end

function my_shortest_path(
    travelTimeGraph::TravelTimeGraph,
    src::Int,
    dst::Int;
    dists::Vector{Float64},
    parents::Vector{Int},
    queue::PriorityQueue{Int,Float64},
    force_elementarity::Bool=false,
)
    shortestPath, pathCost = my_dijkstra(
        travelTimeGraph.graph,
        src,
        dst,
        travelTimeGraph.costMatrix;
        dists=dists,
        parents=parents,
        queue=queue,
    )
    pathCost -= remove_shortcuts!(shortestPath, travelTimeGraph)
    if force_elementarity && !is_path_admissible(travelTimeGraph, shortestPath)
        shortestPath, pathCost = my_ressource_a_star(
            travelTimeGraph.graph,
            src,
            dst,
            travelTimeGraph.costMatrix,
            travelTimeGraph.networkNodes;
            dists=dists,
            parents=parents,
            queue=queue,
        )
        pathCost -= remove_shortcuts!(shortestPath, travelTimeGraph)
    end
    return shortestPath, pathCost
end