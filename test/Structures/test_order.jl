# Create an instance of Order
bundle_hash = hash("A123")
deliveryDate = 1
commodity1 = OFOND.Commodity(0, hash("A123"), 10, 2.5)
commodity2 = OFOND.Commodity(1, hash("B456"), 5, 3.0)
order = OFOND.Order(bundle_hash, deliveryDate, [commodity1, commodity2])

# Test that Order is not mutable but its content is
@test !ismutable(order)
@test ismutable(order.content)

emptyOrder = OFOND.Order(hash("B456"), deliveryDate)
order1 = OFOND.Order(hash("A123"), 1, [commodity1, commodity1])
# Test (in)equality
@testset "equality" begin
    @test emptyOrder == OFOND.Order(hash("B456"), 1)
    @test order == OFOND.Order(hash("A123"), 1, [commodity1, commodity2])
    @test order == order1
    @test order == OFOND.Order(hash("A123"), 1, OFOND.Commodity[])
    @test emptyOrder != order
end

# Test hashing
@test hash(order) == hash(1, hash("A123"))

# Test add properties
binPack = (x, y, z, t) -> y
order2 = OFOND.add_properties(order, binPack, Int[])
@test order2 == OFOND.Order(
    hash("A123"),
    1,
    [commodity1, commodity2],
    hash(1, hash("A123")),
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

# Test memory affectation
# Commodity1 and order1 content refer all to the same object
@test all(com -> com === commodity1, order1.content)

println("Size of commodity1 : $(Base.summarysize(commodity1))")
println(
    "Size of order1 content : $(Base.summarysize(order1.content)) (vs 2 x size of commodity1 :$(2*Base.summarysize(commodity1)))",
)
println(
    "Size of order content : $(Base.summarysize(order.content)) (vs 2 x size of commodity1 :$(Base.summarysize(commodity1) + Base.summarysize(commodity2)))",
)
println("Size of order1 : $(Base.summarysize(order))")