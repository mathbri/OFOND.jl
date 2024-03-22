# Bundle structure (group of orders with the same origin and destination)

struct Bundle
    supplier :: NetworkNode  # supplier node
    customer :: NetworkNode  # customer node
    orders :: Vector{Order}  # vector of order
    maxPackSize :: Int       # size of the largest commodity in the bundle
end

struct PartialBundle
    supplier :: NetworkNode  # supplier node
    customer :: NetworkNode  # customer node
    orders :: Vector{PartialOrder}  # vector of order
end

function Bundle(partialBundle::PartialBundle)
    orders = Order[Order(partial for partial in partialBundle.orders)]
    maxPackSize = maximum(order -> maximum(com -> com.size, order.content), partialBundle.orders)
    return Bundle(partialBundle.supplier, partialBundle.customer, orders, maxPackSize)
end

# Methods
