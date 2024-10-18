# Testing other object constructors
@testset "Other constructors" begin
    @test OFOND.Order(bundle1, 2) == OFOND.Order(
        hash(supplier1, hash(plant)),
        2,
        OFOND.Commodity[],
        hash(2, hash(supplier1, hash(plant))),
        0,
        Dict{Symbol,Int}(),
        0,
        0.0,
    )
end

@testset "add_properties" begin
    bundle = OFOND.Bundle(supplier1, plant, 1)
    push!(bundle.orders, order3)
    bundle4 = OFOND.add_properties(bundle, network)
    @test bundle4.supplier == supplier1
    @test bundle4.customer == plant
    @test bundle4.idx == 1
    @test bundle4.hash == hash(supplier1, hash(plant))
    @test bundle4.orders == [order3]
    @test bundle4.maxPackSize == 15
    @test bundle4.maxDelTime == 3
end

order = OFOND.add_properties(order3, (x, y, z, t) -> 2, Int[])

@testset "get_lb_transport_units" begin
    @test OFOND.get_lb_transport_units(order, supp1_to_plant) == 1
    @test OFOND.get_lb_transport_units(order, supp1_to_plat) ≈ 0.5
    @test OFOND.get_lb_transport_units(order, xdock_to_port) ≈ 0.5
end

@testset "get_transport_units" begin
    @test OFOND.get_transport_units(order, supp1_to_plant) == 2
    @test OFOND.get_transport_units(order, supp1_to_plat) ≈ 0.5
    @test OFOND.get_transport_units(order, xdock_to_port) == 2
    dummy = OFOND.NetworkArc(:dummy, 1.0, 1, true, 4.0, false, 1.0, 50)
    @test OFOND.get_transport_units(order, dummy) == 0
end

@testset "is node filterable" begin
    @test !OFOND.is_node_filterable(network, 1, [bundle1])
    @test OFOND.is_node_filterable(network, 2, [bundle1])
    @test !OFOND.is_node_filterable(network, 4, [bundle1])
end
