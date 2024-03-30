# Order structure to store corresponding metadata

# TODO : change ffd and giant units to dict to store values for all arc capacities (by arc types or directly values ?)

struct Order
    bundle :: Bundle              # bundle to which the order belongs
    deliveryDate :: Int           # delivery date index in instance time horizon
    content :: Vector{Commodity}  # order content in packages
end

struct OrderUtils
    volume :: Int       # total volume of the order
    bpUnits :: Int     # number of trucks used with ffd loading and base capacity
    giantUnits :: Int   # number of trucks used with giant container loading
    minPackSize :: Int  # size of the smallest commodity in the order
    leadTimeCost :: Float64 # total lead time cost of the order
end
# TODO : add unique commodity vector to order utils ?

# Methods

function OrderUtils(order::Order)
    volume = sum(com -> com.size, order.content)
    bpUnits = 0
    giantUnits = 0
    minPackSize = minimum(com -> com.size, order.content)
end

function OrderUtils(order::Order, binPackAlg::Function, capacity::Int)
    volume = sum(com -> com.size, order.content)
    bpUnits = binPackAlg(Bin[], capacity, order.content)
    giantUnits = ceil(Int, volume / capacity)
    minPackSize = minimum(com -> com.size, order.content)
    leadTimeCost = sum(com -> com.leadTimeCost, order.content)
    return OrderUtils(volume, bpUnits, giantUnits, minPackSize, leadTimeCost)
end

function Base.:(==)(ord1::Order, ord2::Order)
    return (ord1.bundle == ord2.bundle) && (ord1.deliveryDate == ord2.deliveryDate)
end

function get_supplier(order::Order)
    return order.bundle.supplier
end

function get_customer(order::Order)
    return order.bundle.customer
end
