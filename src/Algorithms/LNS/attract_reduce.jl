function attract_reduce_perturbation()
    # Build network graph from instance 
    # Build travel time graph from network graph
    # Copy Solution object

    # Take an arc of the shared network
    # Decide whether you want to attract or reduce flow on this arc
    # Take all bundles corresponding to this choice :
    #     All that do not flow on the arc if attract
    #     Alll that flow on the arc if reduce
    # Generate new paths for the considered bundles 
    # Solve the new or old path milp :
    #     Insert back all the bundles jointly with a milp that considers only a relaxed 
    #     version of bin-packing and decide whether to use the former or the latter path

    # Need for a struct dedicated for relaxed bin-packing structure in solutions ?
    # If not, transform the milp solution into a feasible solution by applying bin-packing heuristics 

    # Return solution
end

# Combine this perturbation with the local search to obtain a better neighbor