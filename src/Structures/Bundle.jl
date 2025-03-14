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

# Average the bundle orders on the whole horizon
function average_bundle(bundle::Bundle, timeHorizon::Int)
    # Computing totals (volume, nb of com, stock cost) on the time horizon and the commodity mean volume
    totVolume = sum(order.volume for order in bundle.orders)
    totCom = sum(length(order.content) for order in bundle.orders)
    totStockCost = sum(order.stockCost for order in bundle.orders)
    # Computing news
    newOrderVolume = totVolume / timeHorizon
    meanComSize = totVolume / totCom
    nCom = ceil(newOrderVolume / meanComSize)
    # Rounding won't have puch impact as we are with m3 / 100
    newComSize = round(newOrderVolume / nCom)
    newComStockCost = totStockCost / nCom
    # Creating 1 new order with commodities of the mean volume  
    newDelDate = bundle.orders[1].deliveryDate
    newContent = [Commodity(0, 0, newComSize, newComStockCost) for _ in 1:nCom]
    newOrder = Order(bundle.hash, newDelDate, newContent)
    return Bundle(
        bundle.supplier, bundle.customer, [newOrder], bundle.idx, bundle.hash, 0, 0
    )
end