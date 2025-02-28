# Commodity structure to store corresponding metadata

# TODO : maybe switch from m3 / 100 to dm3 (m3 / 1000)

struct Commodity
    orderHash::UInt      # hash of the order the commodity belongs
    partNumHash::UInt    # hashing part number for efficient equality comparison
    size::Int            # size of one package in m3 / 100
    weight::Int          # weight of one package in kg
    stockCost::Float64   # stock cost of the commodity
end

# Methods

function Base.hash(com::Commodity)
    return hash(com.partNumHash, com.orderHash)
end

function Base.:(==)(com1::Commodity, com2::Commodity)
    return (com1.orderHash == com2.orderHash) && (com1.partNumHash == com2.partNumHash)
end

# Defining isless to simplify sorting operations by size for commodities
function Base.isless(com1::Commodity, com2::Commodity)
    return Base.isless(com1.size, com2.size)
end

function Base.show(io::IO, com::Commodity)
    return print(
        io,
        "Commodity($(com.orderHash), $(com.partNumHash), $(com.size), $(com.weight), $(com.stockCost))",
    )
end

function Base.zero(::Type{Commodity})
    return Commodity(UInt(0), UInt(0), 0, 0, 0.0)
end

# Change to exponential weights ? 
function commodity_1D(commodity::Commodity; mixing::Bool=false)
    oh, ph = commodity.orderHash, commodity.partNumHash
    size, weight = commodity.size, commodity.weight
    newSize = mixing ? round(Int, (size + weight * SCORE_FACTOR) / 2) : size
    return Commodity(oh, ph, max(size, newSize), 0, commodity.stockCost)
end
