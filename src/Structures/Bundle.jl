# Bundle structure (group of orders with the same origin and destination)

# TODO : transform hashs into shallow copy of objects for easier usage
struct Bundle
    supplier :: UInt        # supplier hash (identifier in network graph)
    customer :: UInt        # customer hash (identifier in network graph)
    orders :: Vector{UInt}  # vector of order hash (identifier in instance's dict of orders)
    maxPackSize :: Int      # size of the largest commodity in the bundle

    Bundle(supplier, customer, orders, maxPackSize) = new(supplier, customer, orders, maxPackSize)
end

# Methods
