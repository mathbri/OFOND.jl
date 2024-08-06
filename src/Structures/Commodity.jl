# Commodity structure to store corresponding metadata

# This contruction makes the commodity mutable, which may impede performance
# Maybe an option is to hash directly the partNumber and keep a dictionnary for the reverse function at writing time 
# TODO : to test

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
    return (com1.orderHash == com2.orderHash) && (com1.partNumHash == com2.partNumHash)
end

part_number(commodity::Commodity) = commodity.data.partNumber

# TODO : this overloads the base size function, maybe change name ?
size(commodity::Commodity) = commodity.data.size

lead_time_cost(commodity::Commodity)::Float64 = commodity.data.leadTimeCost

# Defining isless to simplify sorting operations by size for commodities
function Base.isless(com1::Commodity, com2::Commodity)
    return Base.isless(size(com1), size(com2))
end

function Base.show(io::IO, commodity::Commodity)
    return print(
        io,
        "Commodity($(commodity.orderHash), $(part_number(commodity)), $(size(commodity)), $(lead_time_cost(commodity)))",
    )
end
