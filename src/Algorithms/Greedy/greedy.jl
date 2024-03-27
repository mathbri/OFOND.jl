function greedy_heuristic()
    # Build network graph from instance 
    # Build travel time graph from network graph
    
    # Sort bundle by maximum packaging size

    # For every bundle :
    #     Extract a bundle specific travel time subgraph from the complete one 
    #     Compute travel time arc cost :
    #         For every arc in the bundle subgraph :
    #              If the arc has a linear cost structure : multiply the linear cost with the sumed orders volume
    #              If the arc has a bin-packing cost structure : 
    #                  For each order and corresponding timed arc : 
    #                      If the arc is empty : multiply arc cost with pre-computed ffd packing
    #                      Otherwise : compute explicitly with a bin-packing function the added number of trucks and multiply with arc truck cost
    #         Add regularization cost on the arcs
    #     Compute the shortest path from supplier (with stepsToDelivery = maxDeliveryTime) to customer (with stepsToDelivery = 0)
    #     If path not elementary :
    #         divide opening cot of trucks by 2
    #     If path not elementary :
    #         do not take into account current loading
    #     Store bundle path in Solution object 
    #     Update time space graph :
    #         For all arc in the path, update timed arcs loading with the corresponding bundle order content 

    # Construct and return solution object    
end