# Create an instance of Order
bundle_hash = hash("A123")
deliveryDate = 1
commodity1 = OFOND.Commodity(0, hash("A123"), 10, 2.5)
commodity2 = OFOND.Commodity(1, hash("B456"), 5, 3.0)

order = OFOND.Order(bundle_hash, deliveryDate, [commodity1, commodity2])

# Testing constructors
@testset "Constructors" begin
    #Testing all fileds as equality operator don't test it
    @test order.bundleHash == bundle_hash
    @test order.deliveryDate == deliveryDate
    @test order.content == [commodity1, commodity2]
    @test order.hash == hash(deliveryDate, bundle_hash)
    @test order.volume == 0
    @test order.bpUnits == Dict{Symbol,Int}()
    @test order.minPackSize == 0
    @test order.stockCost == 0.0

    order2 = OFOND.Order(bundle_hash, deliveryDate)
    @test order2.bundleHash == bundle_hash
    @test order2.deliveryDate == deliveryDate
    @test order2.content == OFOND.Commodity[]
    @test order2.hash == hash(deliveryDate, bundle_hash)
    @test order2.volume == 0
    @test order2.bpUnits == Dict{Symbol,Int}()
    @test order2.minPackSize == 0
    @test order2.stockCost == 0.0

    # Test that Order is not mutable but its content is
    @test !ismutable(order)
    @test ismutable(order.content)
end

emptyOrder = OFOND.Order(hash("B456"), deliveryDate)
order1 = OFOND.Order(hash("A123"), 1, [commodity1, commodity1])
# Test (in)equality
@testset "Equality and Hash" begin
    @test emptyOrder == OFOND.Order(hash("B456"), 1)
    @test order == OFOND.Order(hash("A123"), 1, [commodity1, commodity2])
    @test order == order1
    @test order == OFOND.Order(hash("A123"), 1, OFOND.Commodity[])
    @test emptyOrder != order
    # Test hashing
    @test hash(order) == hash(1, hash("A123"))
    # Test memory affectation
    # Commodity1 and order1 content refer all to the same object
    @test all(com -> com === commodity1, order1.content)
end

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

# println("Size of commodity1 : $(Base.summarysize(commodity1))")
# println(
#     "Size of order1 content : $(Base.summarysize(order1.content)) (vs 2 x size of commodity1 :$(2*Base.summarysize(commodity1)))",
# )
# println(
#     "Size of order content : $(Base.summarysize(order.content)) (vs 2 x size of commodity1 :$(Base.summarysize(commodity1) + Base.summarysize(commodity2)))",
# )
# println("Size of order1 : $(Base.summarysize(order))")