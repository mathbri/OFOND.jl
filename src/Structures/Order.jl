# Order structure to store corresponding metadata

# TODO : change ffd and giant units to dict to store values for all arc capacities (by arc types or directly values ?)
struct Order
    bundle :: Bundle              # bundle to which the order belongs
    deliveryDate :: Int           # delivery date index in instance time horizon
    content :: Vector{Commodity}  # order content in packages
    # Packing properties
    volume :: Int                 # total volume of the order
    ffdUnits :: Int               # number of trucks used with ffd loading and base capacity
    giantUnits :: Int             # number of trucks used with giant container loading
    minPackSize :: Int            # size of the smallest commodity in the order
end

struct PartialOrder
    deliveryDate :: Int           # delivery date index in instance time horizon
    content :: Vector{Commodity}  # order content in packages
end

# Methods

function Order(partialOrder::PartialOrder, bundle::Bundle)
    volume = sum(com -> com.size, partialOrder.content)
    ffdUnits = 0
    giantUnits = 0
    minPackSize = minimum(com -> com.size, partialOrder.content)
    return Order(bundle, partialOrder.deliveryDate, partialOrder.content, volume, ffdUnits, giantUnits, minPackSize)
end

function get_supplier(order::Order)
    return order.bundle.supplier
end

function get_customer(order::Order)
    return order.bundle.customer
end
