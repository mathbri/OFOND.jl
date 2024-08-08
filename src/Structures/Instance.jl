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

# Extract a sub instance (either by country or continent) from the instance given
function extract_sub_instance(
    instance::Instance; country::String="", continent::String="", timeHorizon::Int=3
)
    noExtraction = (country == "" && continent == "") || (country != "" && continent != "")
    noExtraction && return instance
    # Redifining network and bundles
    newNetGraph = deepcopy(instance.networkGraph)
    newBundles = Bundle[]
    # If country arg is not empty, filtering with it
    if country != ""
        newBundles = filter(bun -> is_bundle_in_country(bun, country), instance.bundles)
        verticesToRemove = filter(
            n -> is_node_in_country(newNetGraph, n, country), vertices(newNetGraph.graph)
        )
        rem_vertices!(newNetGraph.graph, verticesToRemove)
        # Otherwise, the contient arg is not empty
    else
        newBundles = filter(bun -> is_bundle_in_continent(bun, continent), instance.bundles)
        verticesToRemove = filter(
            n -> is_node_in_continent(newNetGraph, n, continent),
            vertices(newNetGraph.graph),
        )
        rem_vertices!(newNetGraph.graph, verticesToRemove)
    end
    nNode, nLeg, nBun = nv(newNetGraph.graph), ne(newNetGraph.graph), length(newBundles)
    nOrd = sum(length(bundle.orders) for bundle in newBundles)
    nCom = sum(
        sum(length(order.content) for order in bundle.orders) for bundle in newBundles
    )
    @info "Extracted instance has $nNode nodes, $nLeg legs, $nBun bundles, $nOrd orders and $nCom commodities on a $timeHorizon steps time horizon"
    return Instance(
        newNetGraph,
        TravelTimeGraph(newNetGraph, newBundles),
        TimeSpaceGraph(newNetGraph, timeHorizon),
        newBundles,
        timeHorizon,
        instance.dateHorizon[1:timeHorizon],
    )
end