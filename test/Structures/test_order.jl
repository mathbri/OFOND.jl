# Test that Order is mutable
@test ismutable(Order)

# Create an instance of Order
bundle_hash = hash("A123")
deliveryDate = 1
commodity_data = CommodityData(part_num, size, lead_time_cost)
commodity1 = Commodity(0, hash("A123"), CommodityData("A123", 10, 2.5))
commodity2 = Commodity(1, hash("B456"), CommodityData("B456", 5, 3.0))
order = Order(bundle_hash, deliveryDate, [commodity1, commodity2])

# Test equality
emptyOrder = Order(bundle_hash, deliveryDate)
@test emptyOrder == Order(hash("A123"), 1)
@test order == Order(hash("A123"), 1, [commodity1, commodity2])
@test order == Order(hash("A123"), 1, [commodity1, commodity1])
@test order == Order(hash("A123"), 1, [])

# Test inequality
@test emptyOrder != order

# Test hashing
@test hash(order) == hash(1, hash("A123"))

# Test add properties
binPack = (x, y, z) -> y
order2 = add_properties(order, binPack)
@test order2 == Order(
    hash("A123"),
    1,
    [commodity1, commodity2],
    15,
    Dict(
        :direct => 70,
        :cross_plat => 70,
        :delivery => 70,
        :oversea => 65,
        :port_transport => 70,
    ),
    5,
    5.5,
)