# TODO : add a random delivery mode option (in arc cost ? direct or outsource ?)

# For every bundle :
#     Compute network arc cost, either precomputed ffd bin-packing or volume * linear cost
#     Compute the shortest path from supplier to customer on the netwotk graph
#     Store bundle path in Solution object
#     Update time space graph :
#         For all arc in the path, update timed arcs loading with the corresponding bundle order content 

# Construct and return solution object

# Benchmark heuristic where all bundle path are computed as the shortest delivery path on the network graph
function shortest_delivery!(solution::Solution, instance::Instance)
    TTGraph = instance.travelTimeGraph
    TSGraph = instance.timeSpaceGraph
    # Sorting commodities
    sort_order_content!(instance)
    # Computing the shortest delivery possible for each bundle
    for bundle in instance.bundles
        # Retrieving bundle start and end nodes
        suppNode = TTGraph.bundleStartNodes[bundle.idx]
        custNode = TTGraph.bundleEndNodes[bundle.idx]
        # Computing shortest path
        shortestPath = a_star(TTGraph.graph, suppNode, custNode, TTGraph.costMatrix)
        remove_shotcuts!(shortestPath, travelTimeGraph)
        # Adding path to solution
        add_path!(solution, bundle, shortestPath)
        # Updating the bins for each order of the bundle
        for order in bundle.orders
            update_bins!(solution, TSGraph, TTGraph, shortestPath, order; sorted=true)
        end
    end
end

# Average orders volume and either create solution from lower bound solve idea or from milp solve idea

function average_delivery_heuristic()
end