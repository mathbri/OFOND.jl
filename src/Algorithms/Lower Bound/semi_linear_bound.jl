function semi_linear_bound_heuristic()
    # Build network graph from instance 
    # Build travel time graph from network graph

    # For every bundle :
    #     Extract a bundle specific travel time subgraph from the complete one 
    #     Compute travel time arc cost :
    #         For every arc in the bundle subgraph :
    #              If the arc has a linear cost structure : multiply the linear cost with the sumed orders volume
    #              If the arc has a bin-packing cost structure : linearize arc cost and multiply with sumed order volume
    #     Compute the shortest path from supplier (with stepsToDelivery = maxDeliveryTime) to customer (with stepsToDelivery = 0)
    #     Add path cost to the lower bound value
    #     Store bundle path in Solution object 
    #     Update time space graph :
    #         For all arc in the path, update timed arcs loading with the corresponding bundle order content 

    # Construct and return solution object   
end

function semi_linear_bound()
    # Do the same but don't compute the corresponding solution
end