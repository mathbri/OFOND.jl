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
    @info "Adding properties to instance"
    newBundles = Bundle[
        add_properties(bundle, instance.networkGraph) for bundle in instance.bundles
    ]
    for bundle in newBundles
        newOrders = [add_properties(order, bin_packing) for order in bundle.orders]
        empty!(bundle.orders)
        append!(bundle.orders, newOrders)
    end
    newTTGraph = TravelTimeGraph(instance.networkGraph, newBundles)
    @info "Travel-time graph has $(nv(newTTGraph.graph)) nodes and $(ne(newTTGraph.graph)) arcs"
    newTSGraph = TimeSpaceGraph(instance.networkGraph, instance.timeHorizon)
    @info "Time-space graph has $(nv(newTSGraph.graph)) nodes and $(ne(newTSGraph.graph)) arcs"
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
    newNetwork = deepcopy(instance.networkGraph)
    newBundles = Bundle[]
    newVertices = Int[]
    # If country arg is not empty, filtering with it
    if country != ""
        newBundles = filter(bun -> is_bundle_in_country(bun, country), instance.bundles)
        newVertices = filter(
            n -> is_node_in_country(newNetwork, n, country), vertices(newNetwork.graph)
        )
    else
        # Otherwise, the contient arg is not empty
        newBundles = filter(bun -> is_bundle_in_continent(bun, continent), instance.bundles)
        newVertices = filter(
            n -> is_node_in_continent(newNetwork, n, continent), vertices(newNetwork.graph)
        )
    end
    length(newBundles) == 0 && @warn "No bundles in the sub instance"
    # Filtering bundle and orders
    newBundles = [
        remove_orders_outside_horizon(bundle, timeHorizon) for bundle in newBundles
    ]
    newBundles = [bundle for bundle in newBundles if length(bundle.orders) > 0]
    newBundles = [change_idx(bundle, idx) for (idx, bundle) in enumerate(newBundles)]
    newNetGraph, _ = induced_subgraph(instance.networkGraph.graph, newVertices)
    newNetwork = NetworkGraph(newNetGraph)
    nNode, nLeg, nBun = nv(newNetGraph), ne(newNetGraph), length(newBundles)
    nOrd = sum(length(bundle.orders) for bundle in newBundles; init=0)
    nCom = sum(
        sum(length(order.content) for order in bundle.orders) for bundle in newBundles;
        init=0,
    )
    @info "Extracted instance has $nNode nodes, $nLeg legs, $nBun bundles, $nOrd orders and $nCom commodities on a $timeHorizon steps time horizon"
    return Instance(
        newNetwork,
        TravelTimeGraph(newNetwork, newBundles),
        TimeSpaceGraph(newNetwork, timeHorizon),
        newBundles,
        timeHorizon,
        instance.dateHorizon[1:timeHorizon],
    )
end