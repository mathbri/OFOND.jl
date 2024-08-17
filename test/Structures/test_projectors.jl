# Define supplier, platform, and plant
supplier1 = OFOND.NetworkNode("001", :supplier, "FR", "EU", false, 0.0)
supplier2 = OFOND.NetworkNode("002", :supplier, "FR", "EU", false, 0.0)
xdock = OFOND.NetworkNode("004", :xdock, "FR", "EU", true, 1.0)
port_l = OFOND.NetworkNode("005", :pol, "FR", "EU", true, 0.0)
plant = OFOND.NetworkNode("003", :plant, "FR", "EU", false, 0.0)

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
commodity1 = OFOND.Commodity(0, hash("A123"), 10, 2.5)
order1 = OFOND.Order(hash(supplier1, hash(plant)), 1, [commodity1, commodity1])
bundle1 = OFOND.Bundle(supplier1, plant, [order1], 1, hash(supplier1, hash(plant)), 10, 2)

commodity2 = OFOND.Commodity(1, hash("B456"), 15, 3.5)
order2 = OFOND.Order(hash(supplier2, hash(plant)), 1, [commodity2, commodity2])
bundle2 = OFOND.Bundle(supplier2, plant, [order2], 2, hash(supplier2, hash(plant)), 15, 1)

order3 = OFOND.Order(hash(supplier1, hash(plant)), 1, [commodity1, commodity2])
order4 = OFOND.Order(hash(supplier1, hash(plant)), 2, [commodity1, commodity2])
bundle3 = OFOND.Bundle(supplier1, plant, [order3], 3, hash(supplier1, hash(plant)), 10, 3)

bundles = [bundle1, bundle2, bundle3]

# Define TravelTimeGraph and TimeSpaceGraph
TTGraph = OFOND.TravelTimeGraph(network, bundles)
TSGraph = OFOND.TimeSpaceGraph(network, 4)

@testset "Get node step" begin
    supp1step1 = TSGraph.hashToIdx[hash(1, supplier1.hash)]
    @test OFOND.get_node_step_to_delivery(TSGraph, supp1step1, 1) == 0
    @test OFOND.get_node_step_to_delivery(TSGraph, supp1step1, 2) == 1
    supp1step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
    @test OFOND.get_node_step_to_delivery(TSGraph, supp1step3, 1) == 2
end

@testset "Travel Time projector" begin
    # On the same time step so 0 steps to delivery
    supp2step1 = TSGraph.hashToIdx[hash(1, supplier2.hash)]
    @test OFOND.travel_time_projector(TTGraph, TSGraph, supp2step1, 1, 1) ==
        TTGraph.hashToIdx[hash(0, supplier2.hash)]
    # 2 time steps from delivery so too much
    supp2step3 = TSGraph.hashToIdx[hash(3, supplier2.hash)]
    @test OFOND.travel_time_projector(TTGraph, TSGraph, supp2step3, 1, 1) == -1
    # 1 time step from delivery so ok
    supp2step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
    @test OFOND.travel_time_projector(TTGraph, TSGraph, supp2step4, 1, 1) ==
        TTGraph.hashToIdx[hash(1, supplier2.hash)]
    # Tests with other nodes
    xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
    @test OFOND.travel_time_projector(TTGraph, TSGraph, xdockStep3, 1, 1) == -1
    xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
    @test OFOND.travel_time_projector(TTGraph, TSGraph, xdockStep4, 1, 1) ==
        TTGraph.hashToIdx[hash(1, xdock.hash)]
    # Tests with other del dates and max del time
    portStep2 = TSGraph.hashToIdx[hash(2, port_l.hash)]
    @test OFOND.travel_time_projector(TTGraph, TSGraph, portStep2, 1, 2) == -1
    @test OFOND.travel_time_projector(TTGraph, TSGraph, portStep2, 1, 3) ==
        TTGraph.hashToIdx[hash(3, port_l.hash)]
    @test OFOND.travel_time_projector(TTGraph, TSGraph, portStep2, 2, 3) ==
        TTGraph.hashToIdx[hash(0, port_l.hash)]
    portStep3 = TSGraph.hashToIdx[hash(3, port_l.hash)]
    @test OFOND.travel_time_projector(TTGraph, TSGraph, portStep3, 1, 2) ==
        TTGraph.hashToIdx[hash(2, port_l.hash)]
    @test OFOND.travel_time_projector(TTGraph, TSGraph, portStep3, 1, 1) == -1
    @test OFOND.travel_time_projector(TTGraph, TSGraph, portStep3, 1, 3) ==
        TTGraph.hashToIdx[hash(2, port_l.hash)]
    @test OFOND.travel_time_projector(TTGraph, TSGraph, portStep3, 2, 3) ==
        TTGraph.hashToIdx[hash(3, port_l.hash)]
end

@testset "Time Space projector" begin
    # 1 time step from delivery so delivery date - 1 unless first node that gives last time step
    supp2fromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
    @test OFOND.time_space_projector(TTGraph, TSGraph, supp2fromDel1, 1) ==
        TSGraph.hashToIdx[hash(4, supplier2.hash)]
    @test OFOND.time_space_projector(TTGraph, TSGraph, supp2fromDel1, 3) ==
        TSGraph.hashToIdx[hash(2, supplier2.hash)]
    # 0 time step from delivery so same time step as delivery date
    supp2fromDel0 = TTGraph.hashToIdx[hash(0, supplier2.hash)]
    @test OFOND.time_space_projector(TTGraph, TSGraph, supp2fromDel0, 2) ==
        TSGraph.hashToIdx[hash(2, supplier2.hash)]
    @test OFOND.time_space_projector(TTGraph, TSGraph, supp2fromDel0, 4) ==
        TSGraph.hashToIdx[hash(4, supplier2.hash)]
    # Tests with other nodes
    xdockFromDel3 = TTGraph.hashToIdx[hash(3, xdock.hash)]
    @test OFOND.time_space_projector(TTGraph, TSGraph, xdockFromDel3, 4) ==
        TSGraph.hashToIdx[hash(1, xdock.hash)]
    portFromDel2 = TTGraph.hashToIdx[hash(2, port_l.hash)]
    @test OFOND.time_space_projector(TTGraph, TSGraph, portFromDel2, 3) ==
        TSGraph.hashToIdx[hash(1, port_l.hash)]
    # Will give port on time step 5 which is not possible
    @test_throws KeyError OFOND.time_space_projector(TTGraph, TSGraph, portFromDel2, 7)
end

@testset "Projectors wrappers" begin
    # travel time with order and bundle
    xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
    portStep2 = TSGraph.hashToIdx[hash(2, port_l.hash)]
    @test OFOND.travel_time_projector(TTGraph, TSGraph, 1, order1, bundle2) == -1
    @test OFOND.travel_time_projector(TTGraph, TSGraph, xdockStep4, order2, bundle2) ==
        TTGraph.hashToIdx[hash(1, xdock.hash)]
    @test OFOND.travel_time_projector(TTGraph, TSGraph, portStep2, order3, bundle3) ==
        TTGraph.hashToIdx[hash(3, port_l.hash)]
    # travel time arc
    supp2step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
    plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]
    @test OFOND.travel_time_projector(
        TTGraph, TSGraph, supp2step4, plantStep1, order2, bundle2
    ) == (
        TTGraph.hashToIdx[hash(1, supplier2.hash)], TTGraph.hashToIdx[hash(0, plant.hash)]
    )
    # time space arc that can't be projected on the travel time graph
    supp2step1 = TSGraph.hashToIdx[hash(1, supplier2.hash)]
    xdockStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]
    @test OFOND.travel_time_projector(
        TTGraph, TSGraph, supp2step1, xdockStep2, order2, bundle2
    ) == (-1, -1)
    # time space with order 
    supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
    @test OFOND.time_space_projector(TTGraph, TSGraph, supp1FromDel3, order1) ==
        TSGraph.hashToIdx[hash(2, supplier1.hash)]
    # time space arc
    xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
    @test OFOND.time_space_projector(
        TTGraph, TSGraph, supp1FromDel3, xdockFromDel2, order4
    ) == (
        TSGraph.hashToIdx[hash(3, supplier1.hash)], TSGraph.hashToIdx[hash(4, xdock.hash)]
    )
    # time space path
    portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
    plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
    TTPath = [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]
    @test OFOND.time_space_projector(TTGraph, TSGraph, TTPath, order3) == [
        TSGraph.hashToIdx[hash(2, supplier1.hash)],
        TSGraph.hashToIdx[hash(3, xdock.hash)],
        TSGraph.hashToIdx[hash(4, port_l.hash)],
        TSGraph.hashToIdx[hash(1, plant.hash)],
    ]
end