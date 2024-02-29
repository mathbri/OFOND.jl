# Order structure to store corresponding metadata

# TODO : transform hashs into shallow copy of objects for easier usage
struct Order
    # Defining properties
    supplier :: UInt            # supplier of the order
    customer :: UInt            # customer of the order
    deliveryDate :: Int         # delivery date index in instance time horizon
    # Packing properties
    content :: Dict{UInt, Int}  # order content in packages
    volume :: Int               # total volume of the order
    ffdUnits :: Int            # number of trucks used with ffd loading and base capacity
    giantUnits :: Int          # number of trucks used with giant container loading
    minPackSize :: Int          # size of the smallest commodity in the order
    maxPackSize :: Int          # size of the largest commodity in the order
end

# Methods
