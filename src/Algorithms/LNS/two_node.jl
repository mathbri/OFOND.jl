function two_node_perturbation()
    # Build network graph from instance 
    # Build travel time graph from network graph
    # Copy Solution object

    # Take two node of the shared network
    # Take all bundles that flow from the first node to the second node
    # Solve the two node perturbation milp :
    #     Insert back all the bundles jointly with a milp that considers only a relaxed version of bin-packing

    # Need for a struct dedicated for relaxed bin-packing structure in solutions ?
    # If not, transform the milp solution into a feasible solution by applying bin-packing heuristics 

    # Return solution
end

# Combine this perturbation with the local search to obtain a better neighbor