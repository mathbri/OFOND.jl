# Order structure to store corresponding metadata

# TODO : check whether the size of the vector of commodity will be a problem 
# TODO : add unique commodity vector to order ?

# Maybe it would be more efficient to store commodities and quantities in different vector 
# It would therefore need to differentiate between ffd for a vector of commodities -> refilling bins 
# and ffd for an order as the implementation would not be the same -> filling bins

struct Order
    # Core fields
    bundleHash::UInt            # hash of the bundle to which the order belongs
    deliveryDate::Int           # delivery date index in instance time horizon
    content::Vector{Commodity}  # order content in packages
    # Properties
    hash::UInt                 # hash of the order
    volume::Int                 # total volume of the order
    bpUnits::Dict{Symbol,Int}  # number of trucks used with bin packing function given
    minPackSize::Int            # size of the smallest commodity in the order
    leadTimeCost::Float64       # total lead time cost of the order
end

function Order(bunH::UInt, delDate::Int)
    return Order(
        bunH, delDate, Commodity[], hash(delDate, bunH), 0, Dict{Symbol,Int}(), 0, 0.0
    )
end

function Order(bunH::UInt, delDate::Int, content::Vector{Commodity})
    return Order(bunH, delDate, content, hash(delDate, bunH), 0, Dict{Symbol,Int}(), 0, 0.0)
end

# Methods

function Base.:(==)(ord1::Order, ord2::Order)
    return (ord1.bundleHash == ord2.bundleHash) && (ord1.deliveryDate == ord2.deliveryDate)
end

function Base.hash(order::Order)
    return hash(order.deliveryDate, order.bundleHash)
end

# Add useful properties to the order
function add_properties(order::Order, bin_packing::Function)
    volume = sum(com -> size(com), order.content)
    for arcType in BP_ARC_TYPES
        capacity = arcType == :oversea ? SEA_CAPACITY : LAND_CAPACITY
        bpUnits[arcType] = bin_packing(Bin[], capacity, order.content)
    end
    minPackSize = minimum(com -> size(com), order.content)
    leadTimeCost = sum(com -> lead_time_cost(com), order.content)
    return Order(
        order.bundle,
        order.deliveryDate,
        order.content,
        order.hash,
        volume,
        bpUnits,
        minPackSize,
        leadTimeCost,
    )
end
