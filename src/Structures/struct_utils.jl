# Useful functions using / connecting multiple structures

# TODO : check whether these constructirs are still useful !

function Order(bundle::Bundle, deliveryDate::Int)
    return Order(bundle.hash, deliveryDate)
end

function add_properties(bundle::Bundle, network::NetworkGraph)
    supp, cust, i, h = bundle.supplier, bundle.customer, bundle.idx, bundle.hash
    maxPackSize = maximum(order -> maximum(com -> com.size, order.content), bundle.orders)
    maxDelTime = if haskey(network.graph, supp.hash, cust.hash)
        max(network.graph[supp.hash, cust.hash].travelTime, network.graph[]["meanOversea"])
    else
        network.graph[]["maxLeg"]
    end
    return Bundle(supp, cust, bundle.orders, i, h, maxPackSize, maxDelTime + 1)
end

function get_lb_transport_units(order::Order, arcData::NetworkArc)
    # If the arc is shared or already linear
    arcData.type != :direct && return (order.volume / arcData.capacity)
    # If the arc is direct
    return ceil(order.volume / arcData.capacity)
end

function get_transport_units(order::Order, arcData::NetworkArc)
    # If the arc has linear cost
    arcData.isLinear && return (order.volume / arcData.capacity)
    # If the arc is consolidated
    return get(order.bpUnits, arcData.type, 0)
end

function is_node_filterable(networkGraph::NetworkGraph, node::Int, bundles::Vector{Bundle})
    nodeData = networkGraph.graph[label_for(networkGraph.graph, node)]
    !(nodeData.type in [:supplier, :plant]) && return false
    if nodeData.type == :supplier
        return findfirst(b -> b.supplier == nodeData, bundles) === nothing
    else
        return findfirst(b -> b.customer == nodeData, bundles) === nothing
    end
end