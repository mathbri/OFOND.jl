function two_node_incremental_local_search()
    # Build network graph from instance 
    # Build travel time graph from network graph
    # Copy Solution object (to have a best solution and a current solution that you modify on the fly)

    # At each iteration :
    #     Take two node of the shared network
    #     Take all bundles that flow from the first node to the second node
    #     For every such bundle :
    #         Do a greedy bundle introduction but only between the two nodes considered
    #     If the cost is better than the best one encountered so far :
    #         Store the new best solution inplace of the old one 
    #     Otherwise, revert the current solution to its previous state

    # Return the best solution
end