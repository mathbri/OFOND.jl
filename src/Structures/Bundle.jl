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

function is_bundle_in_country(bundle::Bundle, country::String)
    return bundle.supplier.country == country && bundle.customer.country == country
end

function is_bundle_in_continent(bundle::Bundle, continent::String)
    return bundle.supplier.continent == continent && bundle.customer.continent == continent
end

function is_bundle_in_continents(bundle::Bundle, continents::Vector{String})
    return bundle.supplier.continent in continents &&
           bundle.customer.continent in continents
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

function remove_orders_outside_frame(bundle::Bundle, timeStart::Int, timeEnd::Int)
    newOrders = filter(order -> timeStart <= order.deliveryDate <= timeEnd, bundle.orders)
    return Bundle(
        bundle.supplier,
        bundle.customer,
        newOrders,
        bundle.idx,
        bundle.hash,
        bundle.maxPackSize,
        bundle.maxDelTime,
    )
end

# Split the bundle according to part numbers 
# The properties are not recomputed here, no its needs recomputation
function split_bundle(bundle::Bundle, startIdx::Int)
    # Gather al part numbers in the bundle
    partNums = Set{UInt}()
    for order in bundle.orders
        partNums = union(partNums, map(com -> com.partNumHash, order.content))
    end
    # Creating one bundle per part number
    newBundles = Bundle[]
    for (i, partNum) in enumerate(partNums)
        newHash = hash(bundle.supplier, hash(bundle.customer, partNum))
        newOrders = Order[]
        # Creating orders only composed of the partNum 
        for order in bundle.orders
            if count(com -> com.partNumHash == partNum, order.content) > 0
                newContent = filter(com -> com.partNumHash == partNum, order.content)
                newBunOrder = Order(order.hash, order.deliveryDate, newContent)
                push!(newOrders, newBunOrder)
            end
        end
        newIdx = startIdx + i - 1
        newBundle = Bundle(
            bundle.supplier, bundle.customer, newOrders, newIdx, newHash, 0, 0
        )
        push!(newBundles, newBundle)
    end
    return newBundles
end