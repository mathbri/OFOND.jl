# Instance structure to store problem metadata

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
    dateHorizon::Vector{Dates}
end

# Methods

# Computing all objects properties
function add_properties(instance::Instance, bin_packing::Function)
    newBundles = Bundle[
        add_properties(bundle, instance.networkGraph) for bundle in instance.bundles
    ]
    for bundle in newBundles
        bundle.orders = [add_properties(order, bin_packing) for order in bundle.orders]
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
            sort!(order.content; by=com -> com.size, rev=true)
        end
    end
end

function analyze_instance() end