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
    # Fields needed for writing the solution
    dates::Vector{String}
    partNumbers::Dict{UInt,String}
    prices::Dict{UInt,String}
end

# Methods

# Computing all objects properties
function add_properties(instance::Instance, bin_packing::Function, CAPACITIES::Vector{Int})
    @info "Adding properties to instance"
    newBundles = Bundle[
        add_properties(bundle, instance.networkGraph) for bundle in instance.bundles
    ]
    for bundle in newBundles
        newOrders = [
            add_properties(order, bin_packing, CAPACITIES) for order in bundle.orders
        ]
        empty!(bundle.orders)
        append!(bundle.orders, newOrders)
    end
    newTTGraph = TravelTimeGraph(instance.networkGraph, newBundles)
    @info "Travel-time graph has $(nv(newTTGraph.graph)) nodes and $(ne(newTTGraph.graph)) arcs"
    # Checking a path exists for every bundle in the travel time graph 
    noPaths = [
        bundle.idx for bundle in newBundles if !has_path(
            newTTGraph.graph,
            newTTGraph.bundleSrc[bundle.idx],
            newTTGraph.bundleDst[bundle.idx],
        )
    ]
    if length(noPaths) > 0
        throw(
            ErrorException(
                "Some bundles have no path in the travel time graph : $(join(noPaths, ", "))",
            ),
        )
    end
    newTSGraph = TimeSpaceGraph(instance.networkGraph, instance.timeHorizon)
    @info "Time-space graph has $(nv(newTSGraph.graph)) nodes and $(ne(newTSGraph.graph)) arcs"
    return Instance(
        instance.networkGraph,
        newTTGraph,
        newTSGraph,
        newBundles,
        instance.timeHorizon,
        instance.dates,
        instance.partNumbers,
        instance.prices,
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
    nComU = sum(
        sum(length(unique(order.content)) for order in bundle.orders) for
        bundle in newBundles;
        init=0,
    )
    @info "Extracted instance has $nNode nodes, $nLeg legs, $nBun bundles, $nOrd orders and $nCom commodities ($nComU unique) on a $timeHorizon steps time horizon"
    return Instance(
        newNetwork,
        TravelTimeGraph(newNetwork, newBundles),
        TimeSpaceGraph(newNetwork, timeHorizon),
        newBundles,
        timeHorizon,
        instance.dates[1:timeHorizon],
        instance.partNumbers,
        instance.prices,
    )
end

function instance_1D(instance::Instance; mixing::Bool=false)
    # Changing all commodities with a new size 
    newBundles = [bundle_1D(bundle; mixing=mixing) for bundle in instance.bundles]
    @info "Changed instance to 1D (mixing = $mixing)"
    return Instance(
        instance.networkGraph,
        TravelTimeGraph(instance.networkGraph, newBundles),
        instance.timeSpaceGraph,
        newBundles,
        instance.timeHorizon,
        instance.dates,
        instance.partNumbers,
        instance.prices,
    )
end