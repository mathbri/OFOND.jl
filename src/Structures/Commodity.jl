# Commodity structure to store corresponding metadata

# TODO : a lot of commodities so maybe use the most lightwieght data structures like string15 and Int8 if memory problems occurs
struct CommodityData
    partNumber::String     # part number of the commodity
    size::Int              # size of one package in m3 / 100 
    leadTimeCost::Float64  # lead time cost of the commodity
end

struct Commodity
    orderHash::UInt      # hash of the order the commodity belongs
    partNumHash::UInt    # hashing part number for efficient equality comparison
    data::CommodityData  # (shared) data of the commodity
end

# Methods

function Base.:(==)(com1::Commodity, com2::Commodity)
    return (com1.orderHash == com2.orderHash) && (ord1.partNumHash == ord2.partNumHash)
end

part_number(commodity::Commodity) = commodity.data.partNumber

size(commodity::Commodity) = commodity.data.size

lead_time_cost(commodity::Commodity) = commodity.data.leadTimeCost
