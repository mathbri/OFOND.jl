# Define TravelTimeGraph and TimeSpaceGraph
TTGraph = OFOND.TravelTimeGraph(network, bundles)
TSGraph = OFOND.TimeSpaceGraph(network, 4)

@testset "Get node step" begin
    supp1step1 = TSGraph.hashToIdx[hash(1, supplier3.hash)]
    @test OFOND.get_node_step_to_delivery(TSGraph, supp1step1, 1) == 0
    @test OFOND.get_node_step_to_delivery(TSGraph, supp1step1, 2) == 1
    supp1step3 = TSGraph.hashToIdx[hash(3, supplier3.hash)]
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
    @test_warn "Could not project node 16 (Node(005, pol)) on step to del 2 for delivery date 7 -> time step 5 (time horizon = [1, ..., 4])" OFOND.time_space_projector(
        TTGraph, TSGraph, portFromDel2, 7
    )
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
    supp3FromDel3 = TTGraph.hashToIdx[hash(3, supplier3.hash)]
    @test OFOND.time_space_projector(TTGraph, TSGraph, supp3FromDel3, order1) ==
        TSGraph.hashToIdx[hash(2, supplier3.hash)]
    # time space arc
    xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
    @test OFOND.time_space_projector(
        TTGraph, TSGraph, supp3FromDel3, xdockFromDel2, order4
    ) == (
        TSGraph.hashToIdx[hash(3, supplier3.hash)], TSGraph.hashToIdx[hash(4, xdock.hash)]
    )
    # time space path
    portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
    plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
    TTPath = [supp3FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]
    @test OFOND.time_space_projector(TTGraph, TSGraph, TTPath, order3) == [
        TSGraph.hashToIdx[hash(2, supplier3.hash)],
        TSGraph.hashToIdx[hash(3, xdock.hash)],
        TSGraph.hashToIdx[hash(4, port_l.hash)],
        TSGraph.hashToIdx[hash(1, plant.hash)],
    ]
end