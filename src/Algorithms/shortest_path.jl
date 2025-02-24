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

function shortest_path()
    # TODO : tranfer the corresponding function from the travel time graph file
end