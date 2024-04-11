# Order structure to store corresponding metadata

# TODO : check whether the size of the vector of commodity will be a problem 
# TODO : add unique commodity vector to order ?

struct Order
    # Core fields
    bundle::Bundle              # bundle to which the order belongs
    deliveryDate::Int           # delivery date index in instance time horizon
    content::Vector{Commodity}  # order content in packages
    # Properties
    volume::Int                 # total volume of the order
    bpUnits::Dict{Symbol,Int}  # number of trucks used with bin packing function given
    minPackSize::Int            # size of the smallest commodity in the order
    leadTimeCost::Float64       # total lead time cost of the order
end

function Order(bundle::Bundle, deliveryDate::Int)
    return Order(bundle, deliveryDate, Commodity[], 0, Dict{Symbol,Int}(), 0, 0.0)
end

# Methods

function Base.:(==)(ord1::Order, ord2::Order)
    return (ord1.bundle.hash == ord2.bundle.hash) &&
           (ord1.deliveryDate == ord2.deliveryDate)
end

function get_supplier(order::Order)
    return order.bundle.supplier
end

function get_customer(order::Order)
    return order.bundle.customer
end

# Add useful properties to the order
function add_properties(order::Order, bin_packing::Function)
    volume = sum(com -> com.size, order.content)
    for arcType in BP_ARC_TYPES
        capacity = arcType == :oversea ? SEA_CAPACITY : LAND_CAPACITY
        bpUnits[arcType] = bin_packing(Bin[], capacity, order.content)
    end
    minPackSize = minimum(com -> com.size, order.content)
    leadTimeCost = sum(com -> get_lead_time_cost(com), order.content)
    return Order(
        order.bundle,
        order.deliveryDate,
        order.content,
        volume,
        bpUnits,
        minPackSize,
        leadTimeCost,
    )
end
