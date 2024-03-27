# Bundle structure (group of orders with the same origin and destination)

struct Bundle
    supplier :: NetworkNode  # supplier node
    customer :: NetworkNode  # customer node
    orders :: Vector{Order}  # vector of order
end

struct BundleUtils
    maxPackSize :: Int       # size of the largest commodity in the bundle
    orderUtils :: Vector{OrderUtils}  # vector of order utils
end

function BundleUtils(bundle::Bundle)
    maxPackSize = maximum(order -> maximum(com -> com.size, order.content), bundle.orders)
    orderUtils = OrderUtils[OrderUtils(order) for order in bundle.orders]
    return BundleUtils(maxPackSize, orderUtils)
end

function BundleUtils(bundle::Bundle, binPackAlg::Function, capacity::Int)
    maxPackSize = maximum(order -> maximum(com -> com.size, order.content), bundle.orders)
    orderUtils = OrderUtils[OrderUtils(order, binPackAlg, capacity) for order in bundle.orders]
    return BundleUtils(maxPackSize, orderUtils)
end

# Methods
