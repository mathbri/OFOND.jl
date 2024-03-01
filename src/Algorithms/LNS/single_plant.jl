function single_plant_perturbation()
    # Build network graph from instance 
    # Build travel time graph from network graph
    # Copy Solution object

    # Take a plant of the network
    # Take all bundles that flow to this plant
    # Solve the single plant perturbation milp :
    #     Insert back all the bundles jointly with a milp that considers only a relaxed version of bin-packing

    # Need for a struct dedicated for relaxed bin-packing structure in solutions ?
    # If not, transform the milp solution into a feasible solution by applying bin-packing heuristics 

    # Return solution
end

# Combine this perturbation with the local search to obtain a better neighbor