function bundle_reintroduction_local_search()
    # Build network graph from instance 
    # Build travel time graph from network graph
    # Copy Solution object (to have a best solution and a current solution that you modify on the fly)

    # At each iteration :
    #     For every bundle (or subset of bundles if specified) :
    #         Remove the bundle from the current solution 
    #         Store previous state of all arcs modified by this removal
    #         Insert it back greedily
    #     If the cost is better than the best one encountered so far :
    #         Store the new best solution inplace of the old one 
    #     Otherwise, revert the current solution to its previous state

    # Return the best solution
end

# Turn this local search into an operator by doing it just for one bundle