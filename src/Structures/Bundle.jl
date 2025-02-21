# Bundle structure (group of orders with the same origin and destination)

# TODO : implement the following
# As he way to create bundles will evolve, the hash will become the unique identifier of bundles 
# and won't be computed upon object creation but directly be a data given by files

struct Bundle
    # Core fields
    supplier::NetworkNode  # supplier node
    customer::NetworkNode  # customer node
    orders::Vector{Order}  # vector of order
    # Properties
    idx::Int               # index in the instance vector (fast and easy retrieval of informations)
    hash::UInt             # hash of the bundle (fast and easy retrieval of informations)
    maxPackSize::Int       # size of the largest commodity in the bundle
    maxDelTime::Int        # maximum number of steps for delivery authorized
end

function Bundle(supplier::NetworkNode, customer::NetworkNode, idx::Int)
    return Bundle(supplier, customer, Order[], idx, hash(supplier, hash(customer)), 0, 0)
end

function Base.hash(bundle::Bundle)
    return hash(bundle.supplier, hash(bundle.customer))
end

function Base.:(==)(bun1::Bundle, bun2::Bundle)
    return bun1.hash == bun2.hash
end

function idx(bundles::Vector{Bundle})
    return map(bundle -> bundle.idx, bundles)
end

function Base.show(io::IO, bundle::Bundle)
    return print(io, "Bundle($(bundle.supplier), $(bundle.customer), idx=$(bundle.idx))")
end

function is_bundle_in_country(bundle::Bundle, country::String)
    return bundle.supplier.country == country && bundle.customer.country == country
end

function is_bundle_in_continent(bundle::Bundle, continent::String)
    return bundle.supplier.continent == continent && bundle.customer.continent == continent
end

function change_idx(bundle::Bundle, idx::Int)
    return Bundle(
        bundle.supplier,
        bundle.customer,
        bundle.orders,
        idx,
        bundle.hash,
        bundle.maxPackSize,
        bundle.maxDelTime,
    )
end

function remove_orders_outside_horizon(bundle::Bundle, timeHorizon::Int)
    return Bundle(
        bundle.supplier,
        bundle.customer,
        [order for order in bundle.orders if order.deliveryDate <= timeHorizon],
        bundle.idx,
        bundle.hash,
        bundle.maxPackSize,
        bundle.maxDelTime,
    )
end

function bundle_1D(bundle::Bundle; mixing::Bool=false)
    return Bundle(
        bundle.supplier,
        bundle.customer,
        [order_1D(order; mixing=mixing) for order in bundle.orders],
        bundle.idx,
        bundle.hash,
        bundle.maxPackSize,
        bundle.maxDelTime,
    )
end
