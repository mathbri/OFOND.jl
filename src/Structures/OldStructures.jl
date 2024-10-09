# File to keep old structures and test the saving in space

struct OldCommodityData
    partNumber::String
    size::Int
    cost::Float64
end

struct OldCommodity
    orderHash::UInt
    partNumHash::UInt
    data::OldCommodityData
end

struct OldOrder
    bundleHash::UInt
    deliveryDate::String
    content::Vector{OldCommodity}
    hash::UInt
end

struct OldBundle
    supplierAccount::String
    supplierType::String
    customerAccount::String
    customerType::String
    orders::Vector{OldOrder}
end

struct OptOrder
    bundleHash::UInt
    deliveryDate::Int
    content::Vector{Commodity}
end

struct OptBundle
    suppHash::UInt
    custHash::UInt
    orders::Vector{OptOrder}
end

# Easily gauge bundle, network node and commodity space change

# For the full instance, juste plot the summary_size of pre-computation objects for travel time and time space graphs

# For computed arcs and bin packings 
# old situation : all arcs of the travel time graph and all common arc of travel time graph * time horizon for bin packing
# new situation : add counters when an arc is visited and when a packing is computed and divide both by the number of bundles