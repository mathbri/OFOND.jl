# Useful functions using / connecting multiple structures

function add_properties(bundle::Bundle, network::NetworkGraph)
    maxPackSize = maximum(order -> maximum(com -> com.size, order.content), bundle.orders)
    maxDelTime = 1 + network.graph[bundle.supplier.hash, bundle.customer.hash].travelTime
    return Bundle(
        bundle.supplier,
        bundle.customer,
        bundle.orders,
        bundle.idx,
        bundle.hash,
        maxPackSize,
        maxDelTime,
    )
end

function get_lb_transport_units(order::Order, arcData::NetworkArc)
    # If the arc is shared
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

function sort_order_content!(instance::Instance)
    for bundle in instance.bundles
        for order in bundle.orders
            sort!(order.content; by=com -> com.size, rev=true)
        end
    end
end