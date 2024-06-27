# Bundle structure (group of orders with the same origin and destination)

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
