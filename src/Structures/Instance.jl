# Instance structure to store problem metadata

# TODO : think about the following
# A lot of metadata of the problem are superfluous to solve the problem (dates, coordinates, ...)
# The instance could be reduced to only the data needed with the metadata needed for extraction stored somewhere else

struct Instance
    # Network 
    networkGraph::NetworkGraph
    # Travel time graph
    travelTimeGraph::TravelTimeGraph
    # Time space graph
    timeSpaceGraph::TimeSpaceGraph
    # Commodities ordered in bundles
    bundles::Vector{Bundle}
    # Time Horizon 
    timeHorizon::Int
    dateHorizon::Vector{Date}
end

# Methods

# Computing all objects properties
function add_properties(instance::Instance, bin_packing::Function)
    newBundles = Bundle[
        add_properties(bundle, instance.networkGraph) for bundle in instance.bundles
    ]
    for bundle in newBundles
        newOrders = [add_properties(order, bin_packing) for order in bundle.orders]
        empty!(bundle.orders)
        append!(bundle.orders, newOrders)
    end
    newTTGraph = TravelTimeGraph(instance.networkGraph, newBundles)
    newTSGraph = TimeSpaceGraph(instance.networkGraph, instance.timeHorizon)
    return Instance(
        instance.networkGraph,
        newTTGraph,
        newTSGraph,
        newBundles,
        instance.timeHorizon,
        instance.dateHorizon,
    )
end

# Sorting once and for all order contents
function sort_order_content!(instance::Instance)
    for bundle in instance.bundles
        for order in bundle.orders
            sort!(order.content; rev=true)
        end
    end
end

function analyze_instance() end