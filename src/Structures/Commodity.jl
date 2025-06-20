# Commodity structure to store corresponding metadata

# TODO : maybe switch from m3 / 100 to dm3 (m3 / 1000)
# The idea to mutualize the partNumber, size and stock cost was not a good idea because result in x2 space taken because of new object layer 

struct Commodity
    orderHash::UInt      # hash of the order the commodity belongs
    partNumHash::UInt    # hashing part number for efficient equality comparison
    size::Int            # size of one package in m3 / 100
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

function Base.show(io::IO, commodity::Commodity)
    return print(
        io,
        "Commodity($(commodity.orderHash), $(commodity.partNumHash), $(commodity.size), $(commodity.stockCost))",
    )
end

function Base.zero(::Type{Commodity})
    return Commodity(UInt(0), UInt(0), 0, 0.0)
end
