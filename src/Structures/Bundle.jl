# Bundle structure (group of orders with the same origin and destination)

struct Bundle
    supplier :: NetworkNode  # supplier node
    customer :: NetworkNode  # customer node
    orders :: Vector{Order}  # vector of order
    maxPackSize :: Int       # size of the largest commodity in the bundle

    Bundle(supplier, customer, orders, maxPackSize) = new(supplier, customer, orders, maxPackSize)
end

# Methods
