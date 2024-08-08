# Create Bundle instance
supplier = OFOND.NetworkNode(
    "S1", :supplier, "Supp", Geodesy.LLA(10.0, 10.0), "Fra", "EU", false, 0.1
)
customer = OFOND.NetworkNode(
    "C1", :plant, "Cust", Geodesy.LLA(20.0, 20.0), "Ger", "EU", true, 0.1
)
idx = 1
bundle = OFOND.Bundle(supplier, customer, idx)

# Test that Bundle is mutable
@test !ismutable(bundle)
@test ismutable(bundle.orders)

# Test bundle constructor
@testset "Bundle constructor" begin
    @test bundle.supplier == supplier
    @test bundle.customer == customer
    @test bundle.idx == idx
    @test length(bundle.orders) == 0
    @test bundle.maxPackSize == 0
    @test bundle.maxDelTime == 0
end

# Test hash method
@testset "Bundle hash method" begin
    @test hash(bundle) == hash(supplier, hash(customer))
end

idx = 2
supplier2 = OFOND.NetworkNode(
    "S2", :supplier, "Supp", Geodesy.LLA(10.0, 20.0), "Fra", "EU", false, 0.1
)
bundle2 = OFOND.Bundle(supplier, customer, idx)
bundle3 = OFOND.Bundle(supplier2, customer, idx + 1)

# Test == method
@testset "Bundle == method" begin
    @test bundle == bundle2
    @test bundle != bundle3
end

# Test idx method
@testset "Bundle idx method" begin
    bundles = [bundle, bundle2, bundle3]
    result = OFOND.idx(bundles)
    @test result == [1, 2, 3]
end

# Test order adding
@testset "Adding Order to Bundle" begin
    commodity1 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 10, 2.5))
    order1 = OFOND.Order(hash("A123"), 1, [commodity1, commodity1])
    push!(bundle.orders, order1)
    @test length(bundle.orders) == 1
    @test bundle.orders[1] === order1
    @test all(com -> com === commodity1, bundle.orders[1].content)
end

customer2 = OFOND.NetworkNode(
    "C2", :customer, "Cust", Geodesy.LLA(20.0, 10.0), "Fra", "Asia", false, 0.1
)
bundle4 = OFOND.Bundle(supplier2, customer, idx + 2)

# Test is_bundle_property
@testset "Bundle in country / continent" begin
    @test !OFOND.is_bundle_in_country(bundle1, "Fra")
    @test !OFOND.is_bundle_in_country(bundle1, "Ger")
    @test OFOND.is_bundle_in_country(bundle4, "Fra")

    @test OFOND.is_bundle_in_continent(bundle1, "EU")
    @test !OFOND.is_bundle_in_continent(bundle4, "EU")
end