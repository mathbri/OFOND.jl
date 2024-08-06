# Define supplier, platform, and plant
supplier1 = OFOND.NetworkNode("001", :supplier, "Supp1", LLA(1, 0), "FR", "EU", false, 0.0)
supplier2 = OFOND.NetworkNode("002", :supplier, "Supp2", LLA(0, 1), "FR", "EU", false, 0.0)
xdock = OFOND.NetworkNode("004", :xdock, "XDock1", LLA(2, 1), "FR", "EU", true, 1.0)
port_l = OFOND.NetworkNode("005", :pol, "PortL1", LLA(3, 3), "FR", "EU", true, 0.0)
plant = OFOND.NetworkNode("003", :plant, "Plant1", LLA(4, 4), "FR", "EU", false, 0.0)

# Define arcs between the nodes
supp1_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 50)
supp2_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 50)
supp1_to_plant = OFOND.NetworkArc(:direct, 2.0, 2, false, 10.0, false, 1.0, 50)
supp2_to_plant = OFOND.NetworkArc(:direct, 2.0, 1, false, 10.0, false, 1.0, 50)
plat_to_plant = OFOND.NetworkArc(:delivery, 1.0, 1, true, 4.0, false, 1.0, 50)
xdock_to_port = OFOND.NetworkArc(:cross_plat, 1.0, 1, true, 4.0, false, 0.0, 50)
port_to_plant = OFOND.NetworkArc(:oversea, 1.0, 1, true, 4.0, false, 1.0, 50)

# Add them all to the network
network = OFOND.NetworkGraph()
OFOND.add_node!(network, supplier1)
OFOND.add_node!(network, supplier2)
OFOND.add_node!(network, xdock)
OFOND.add_node!(network, port_l)
OFOND.add_node!(network, plant)
OFOND.add_arc!(network, xdock, plant, plat_to_plant)
OFOND.add_arc!(network, supplier1, xdock, supp1_to_plat)
OFOND.add_arc!(network, supplier2, xdock, supp2_to_plat)
OFOND.add_arc!(network, supplier1, plant, supp1_to_plant)
OFOND.add_arc!(network, supplier2, plant, supp2_to_plant)
OFOND.add_arc!(network, xdock, port_l, xdock_to_port)
OFOND.add_arc!(network, port_l, plant, port_to_plant)

# Define bundles
commodity1 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("B123", 10, 2.5))
order1 = OFOND.Order(hash("C123"), 1, [commodity1, commodity1])
bundle1 = OFOND.Bundle(supplier1, plant, [order1], 1, hash(supplier1, hash(plant)), 10, 2)

commodity2 = OFOND.Commodity(1, hash("B456"), OFOND.CommodityData("C456", 15, 3.5))
order2 = OFOND.Order(hash("D456"), 1, [commodity2, commodity2])
bundle2 = OFOND.Bundle(supplier2, plant, [order2], 2, hash(supplier2, hash(plant)), 15, 1)

order3 = OFOND.Order(hash("E789"), 1, [commodity1, commodity2])
bundle3 = OFOND.Bundle(supplier1, plant, [order3], 3, hash(supplier1, hash(plant)), 10, 3)

bundles = [bundle1, bundle2, bundle3]

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

    @test OFOND.Commodity(order1, OFOND.CommodityData("B123", 10, 2.5)) == OFOND.Commodity(
        hash(1, hash("C123")), hash("B123"), OFOND.CommodityData("B123", 10, 2.5)
    )
end

@testset "add_properties" begin
    bundle = OFOND.Bundle(supplier1, plant, 1)
    push!(bundle.orders, order3)
    bundle4 = OFOND.add_properties(bundle, network)
    @test bundle4 ==
        OFOND.Bundle(supplier1, plant, [order3], 1, hash(supplier1, hash(plant)), 15, 3)
end

order = OFOND.add_properties(order3, (x, y, z) -> 2)

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
    @test !OFOND.is_node_filterable(network, 3, [bundle1])
end
