# Commodity structure to store corresponding metadata

struct Commodity
    order :: Order        # order of the commodity
    partNumber :: String  # part number of the commodity
    size :: Int           # size of one package in m3 / 100 
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
