# Commodity structure to store corresponding metadata

# TODO : a lot of commodities so maybe use the most lightwieght data structures like string15 and Int8
# TODO : another way is to share common data and just have a wrapper to know to which order it belongs
struct Commodity
    order :: Order           # order of the commodity
    partNumber :: String     # part number of the commodity
    partNumHash :: UInt      # hashing part number for efficient equality comparison
    size :: Int              # size of one package in m3 / 100 
    leadTimeCost :: Float64  # lead time cost of the commodity
end

function Commodity(order::Order, partNumber::String, size::Int, leadTimeCost::Float64)
    return Commodity(order, partNumber, hash(partNumber), size, leadTimeCost)
end

# Methods

function Base.:(==)(com1::Commodity, com2::Commodity)
    return (com1.order == com2.order) && (ord1.partNumber == ord2.partNumber)
end

function get_supplier(commodity::Commodity)
    return commodity.order.bundle.supplier
end

function get_customer(commodity::Commodity)
    return commodity.order.bundle.customer
end

function get_delivery_date(commodity::Commodity)
    return commodity.order.deliveryDate
end
