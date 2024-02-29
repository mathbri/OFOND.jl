# TODO : add a random delivery mode option

# Benchmark heuristic where all bundle path are computed as the shortest delivery path on the network graph
function shortest_delivery_heuristic()
    # Build network graph from instance 
    
    # For every bundle :
    #     Compute network arc cost, either precomputed ffd bin-packing or volume * linear cost
    #     Compute the shortest path from supplier to customer on the netwotk graph
    #     Store bundle path in Solution object
    #     Update time space graph :
    #         For all arc in the path, update timed arcs loading with the corresponding bundle order content 

    # Construct and return solution object
end