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
    # Fields needed for writing the solution
    dates::Vector{String}
    partNumbers::Dict{UInt,String}
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
    )
end

function extract_sub_instance2(
    instance::Instance; continents::Vector{String}=[""], timeHorizon::Int=3
)
    # Redifining network and bundles
    newNetwork = deepcopy(instance.networkGraph)
    newBundles = filter(bun -> is_bundle_in_continents(bun, continents), instance.bundles)
    filter!(bun -> bun.maxDelTime <= timeHorizon, newBundles)
    newVertices = filter(
        n -> is_node_in_continents(newNetwork, n, continents), vertices(newNetwork.graph)
    )
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
    )
end

# For instances that are bigger than 3 months
# - create an empty solution for the full problem
# - separate into multiple instances that have a 12 week horizon
# - solve on each instance 
# (can be done in parallel but more in terms of distributed computing rather than multi-threading because already multi-threaded inside)
# - merge all solutions with the same function used now 

# This is not an exact decomposition because there could be deliveries from the last time step of an instance to the first of the next one 
# but it should be an efficient heuristic in terms of coding time and performance trade-off

# Split the instance into multiple instances based on the common time horizon given, 12 weeks by default
function split_instance(instance::Instance, newHorizon::Int=12)
    nFullInstances = div(instance.timeHorizon, newHorizon)
    network = instance.networkGraph
    splitInstances = Instance[]
    for i in 1:nFullInstances
        # Computing the corresponding time frame
        timeStart = (i - 1) * newHorizon + 1
        timeEnd = i * newHorizon
        # Computing the new bundles involved
        newBundles = [
            remove_orders_outside_frame(bundle, timeStart, timeEnd) for
            bundle in instance.bundles
        ]
        filter!(bun -> length(bun.orders) > 0, newBundles)
        newBundles = [change_idx(bundle, idx) for (idx, bundle) in enumerate(newBundles)]
        # Creating the corresponding instance
        newInstance = Instance(
            network,
            TravelTimeGraph(network, newBundles),
            TimeSpaceGraph(network, newHorizon),
            newBundles,
            newHorizon,
            instance.dates[timeStart:timeEnd],
            instance.partNumbers,
        )
        push!(splitInstances, newInstance)
    end
    # Doing the same for the last instance (if there is one)
    if nFullInstances * newHorizon < instance.timeHorizon
        # Computing the corresponding time frame
        timeStart = nFullInstances * newHorizon + 1
        timeEnd = instance.newHorizon
        # Computing the new bundles involved
        newBundles = [
            remove_orders_outside_frame(bundle, timeStart, timeEnd) for
            bundle in instance.bundles
        ]
        filter!(bun -> length(bun.orders) > 0, newBundles)
        newBundles = [change_idx(bundle, idx) for (idx, bundle) in enumerate(newBundles)]
        # Creating the corresponding instance
        newInstance = Instance(
            network,
            TravelTimeGraph(network, newBundles),
            TimeSpaceGraph(network, newHorizon),
            newBundles,
            newHorizon,
            instance.dates[timeStart:timeEnd],
            instance.partNumbers,
        )
        push!(splitInstances, newInstance)
    end
    return splitInstances
end