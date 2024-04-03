# Commodity structure to store corresponding metadata

# TODO : a lot of commodities so maybe use the most lightwieght data structures like string15 and Int8 if memory problems occurs
struct CommodityData
    partNumber :: String     # part number of the commodity
    size :: Int              # size of one package in m3 / 100 
    leadTimeCost :: Float64  # lead time cost of the commodity
end

struct Commodity
    order :: Order         # order of the commodity
    partNumHash :: UInt    # hashing part number for efficient equality comparison
    data :: CommodityData  # (shared) data of the commodity
end

function Commodity(order::Order, data::CommodityData)
    return Commodity(order, hash(data.partNumber), data)
end

# Methods

function Base.:(==)(com1::Commodity, com2::Commodity)
    return (com1.order == com2.order) && (ord1.partNumHash == ord2.partNumHash)
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

function get_part_number(commodity::Commodity)
    return commodity.data.partNumber
end

function get_size(commodity::Commodity)
    return commodity.data.size
end

function get_lead_time_cost(commodity::Commodity)
    return commodity.data.leadTimeCost
end