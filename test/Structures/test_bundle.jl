# Create Bundle instance
supplier = OFOND.NetworkNode("S1", :supplier, "Fra", "EU", false, 0.1)
customer = OFOND.NetworkNode("C1", :plant, "Ger", "EU", true, 0.1)
commodity1 = OFOND.Commodity(0, hash("A123"), 10, 2.5)
commodity2 = OFOND.Commodity(1, hash("B456"), 5, 3.0)
order1 = OFOND.Order(hash("A123"), 1, [commodity1, commodity2])
order2 = OFOND.Order(hash("A123"), 2, [commodity1, commodity2])
orders = [order1, order2]
idx = 1
maxPackSize = 10
maxDelTime = 10
bunH = hash("A123")

bundle = OFOND.Bundle(supplier, customer, orders, idx, bunH, maxPackSize, maxDelTime)

# Test that Bundle is mutable
@test !ismutable(bundle)
@test ismutable(bundle.orders)

# Test bundle constructor
@testset "Constructors" begin
    # Testing all fields as equality operator don't test it
    @test bundle.supplier == supplier
    @test bundle.customer == customer
    @test all(order -> order.bundleHash == bunH, bundle.orders)
    @test [order.deliveryDate for order in bundle.orders] == [1, 2]
    @test [order.content for order in bundle.orders] == [[commodity1, commodity2], [commodity1, commodity2]]
    @test bundle.idx == 1
    @test bundle.hash == bunH
    @test bundle.maxPackSize == 10
    @test bundle.maxDelTime == 10

    # Testing quick constructor
    bundle2 = OFOND.Bundle(supplier, customer, idx)
    @test bundle2.supplier == supplier
    @test bundle2.customer == customer
    @test length(bundle2.orders) == 0
    @test bundle2.idx == 1
    @test bundle2.hash == hash(supplier, hash(customer))
    @test bundle2.maxPackSize == 0
    @test bundle2.maxDelTime == 0
end

idx = 2
supplier2 = OFOND.NetworkNode("S2", :supplier, "Fra", "EU", false, 0.1)
bundle2 = OFOND.Bundle(supplier, customer, idx)
bundle3 = OFOND.Bundle(supplier2, customer, idx + 1)

# Test hash method
@testset "Hash and Equality" begin
    bundle2p = OFOND.Bundle(supplier, customer, idx)
    @test hash(bundle) == hash(supplier, hash(customer))
    @test bundle2 == bundle2p
    @test bundle != bundle2
    # bundles only differs by hash
    bundle1p = OFOND.Bundle(supplier, customer, idx - 1)
    @test bundle != bundle1p
end

order3 = OFOND.Order(hash("A123"), 3, [commodity1, commodity1])

# Test order adding
@testset "Adding Order to Bundle" begin
    push!(bundle.orders, order3)
    @test length(bundle.orders) == 3
    @test bundle.orders[3] === order3
    @test all(com -> com === commodity1, bundle.orders[3].content)
end

customer2 = OFOND.NetworkNode("C2", :customer, "Fra", "Asia", false, 0.1)
bundle4 = OFOND.Bundle(supplier2, customer2, idx + 2)

# Test idx methods
@testset "Idx methods" begin
    bundles = [bundle, bundle2, bundle3]
    result = OFOND.idx(bundles)
    @test result == [1, 2, 3]
    @test bundle4.idx == 4
    @test OFOND.change_idx(bundle4, 5).idx == 5
    bundle45 = OFOND.change_idx(bundle4, 5)
    @test bundle45.idx == 5
end

# Show function 
@testset "Show" begin
    io = IOBuffer()
    OFOND.show(io, bundle)
    content = String(take!(io))
    @test contains(content, "Bundle(Node(S1, supplier), Node(C1, plant), idx=1)")
end

# Test is_bundle_property
@testset "In country / continent" begin
    @test !OFOND.is_bundle_in_country(bundle, "Fra")
    @test !OFOND.is_bundle_in_country(bundle, "Ger")
    @test OFOND.is_bundle_in_country(bundle4, "Fra")

    @test OFOND.is_bundle_in_continent(bundle, "EU")
    @test !OFOND.is_bundle_in_continent(bundle4, "EU")
end

order5 = OFOND.Order(hash("A123"), 5, [commodity1, commodity1])

# test remove orders outside horizon
@testset "Remove orders" begin
    push!(bundle.orders, order5)
    @test length(bundle.orders) == 4
    @test OFOND.remove_orders_outside_horizon(bundle, 4).orders == [order1, order2, order3]
    @test OFOND.remove_orders_outside_frame(bundle, 3, 5).orders == [order3, order5]
end

# Bundle splitting 
@testset "Splitting by part" begin
    newBundles = OFOND.split_bundle_by_part(bundle, 2)
    @test length(newBundles) == 2
    @test OFOND.idx(newBundles) == [2, 3]
    nB1, nB2 = newBundles
    # testing new bundle 1
    @test nB1.supplier == supplier
    @test nB1.customer == customer
    @test length(nB1.orders) == 2
    @test all(order -> all(com -> com === commodity2, order.content), nB1.orders)
    @test nB1.idx == 2
    @test nB1.hash == hash(hash("B456"), hash("A123"))
    @test nB1.maxPackSize == 0
    @test nB1.maxDelTime == 0
    # testing new bundle 2
    @test nB2.supplier == supplier
    @test nB2.customer == customer
    @test length(nB2.orders) == 4
    @test all(order -> all(com -> com === commodity1, order.content), nB2.orders)
    @test nB2.idx == 3
    @test nB2.hash == hash(hash("A123"), hash("A123"))
    @test nB2.maxPackSize == 0
    @test nB2.maxDelTime == 0
end

@testset "Splitting by Time" begin
    newBundles = OFOND.split_bundle_by_time(bundle, 2, 2)
    @test length(newBundles) == 3
    @test OFOND.idx(newBundles) == [2, 3, 4]
    nB1, nB2, nB3 = newBundles
    # testing new bundle 1
    @test nB1.supplier == supplier
    @test nB1.customer == customer
    @test length(nB1.orders) == 2
    @test nB1.orders == [order1, order2]
    @test nB1.idx == 2
    @test nB1.hash == hash(1, bunH)
    @test nB1.maxPackSize == 0
    @test nB1.maxDelTime == 0
    # testing new bundle 2
    @test nB2.supplier == supplier
    @test nB2.customer == customer
    @test length(nB2.orders) == 1
    @test nB2.orders == [order3]
    @test nB2.idx == 3
    @test nB2.hash == hash(2, bunH)
    @test nB2.maxPackSize == 0
    @test nB2.maxDelTime == 0
    # testing new bundle 3
    @test nB3.supplier == supplier
    @test nB3.customer == customer
    @test nB3.orders == [order5]
    @test nB3.idx == 4
    @test nB3.hash == hash(3, bunH)
    @test nB3.maxPackSize == 0
    @test nB3.maxDelTime == 0
end

propOrders = [add_properties(order, (x, y, z, t) -> 1, Int[]) for order in bundle.orders]
bundle2 = OFOND.Bundle(supplier, customer, propOrders, 1, bunH, maxPackSize, maxDelTime)

@testset "Averaging" begin
    newBundle = OFOND.average_bundle(bundle2, 5)
    @test newBundle.supplier == supplier
    @test newBundle.customer == customer
    @test length(newBundle.orders) == 1
    @test newBundle.orders[1].deliveryDate == 1
    @test newBundle.orders[1].content == [OFOND.Commodity(0, 0, 7, 10.5) for _ in 1:2]
    @test newBundle.idx == 1
    @test newBundle.hash == bunH
    @test newBundle.maxPackSize == 0
    @test newBundle.maxDelTime == 0
end
