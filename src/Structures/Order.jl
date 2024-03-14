# Order structure to store corresponding metadata

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

# Methods

function get_supplier(order::Order)
    return order.bundle.supplier
end

function get_customer(order::Order)
    return order.bundle.customer
end
