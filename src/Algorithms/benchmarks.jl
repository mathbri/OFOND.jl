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
    # Sorting commodities
    sort_order_content!(instance)
    # Computing the shortest delivery possible for each bundle
    for bundle in instance.bundles
        # Retrieving bundle start and end nodes
        suppNode = TTGraph.bundleSrc[bundle.idx]
        custNode = TTGraph.bundleDst[bundle.idx]
        # Computing shortest path
        shortestPath = enumerate_paths(
            dijkstra_shortest_paths(TTGraph.graph, suppNode, TTGraph.costMatrix), custNode
        )
        # Adding to solution
        update_solution!(solution, instance, [bundle], [shortestPath]; sorted=true)
    end
end

# TODO 
# Average orders volume and either create solution from lower bound solve idea or from milp solve idea
# Averaging could be done in another way

function average_delivery_heuristic() end