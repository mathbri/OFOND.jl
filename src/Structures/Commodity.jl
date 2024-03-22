# Commodity structure to store corresponding metadata

# TODO : a lot of commodities so maybe use the most lightwieght data structures like string15 and Int8
# TODO : another way is to share common data and just have a wrapper to know to which order it belongs
struct Commodity
    order :: Order           # order of the commodity
    partNumber :: String     # part number of the commodity
    size :: Int              # size of one package in m3 / 100 
    leadTimeCost :: Float64  # lead time cost of the commodity
end

# Methods

function get_supplier(commodity::Commodity)
    return commodity.order.bundle.supplier
end

function get_customer(commodity::Commodity)
    return commodity.order.bundle.customer
end

function get_delivery_date(commodity::Commodity)
    return commodity.order.deliveryDate
end
