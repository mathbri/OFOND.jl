TTGraph = OFOND.TravelTimeGraph(network, bundles)
TSGraph = OFOND.TimeSpaceGraph(network, 4)

supp1Step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]

@testset "Transport units" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    @test OFOND.lb_transport_units(
        sol, TSGraph, supp1Step2, xdockStep3, order1; use_bins=false, giant=false
    ) ≈ 0.4
    @test OFOND.lb_transport_units(
        sol, TSGraph, supp1Step2, xdockStep3, order2; use_bins=false, giant=true
    ) ≈ 0.6
    @test OFOND.lb_transport_units(
        sol, TSGraph, xdockStep3, portStep4, order1; use_bins=false, giant=false
    ) ≈ 0.4
    @test OFOND.lb_transport_units(
        sol, TSGraph, portStep4, plantStep1, order1; use_bins=false, giant=true
    ) ≈ 1.0
    # adding things on the TSGraph to check it is taken into account
    OFOND.first_fit_decreasing!(
        sol.bins[supp1Step2, xdockStep3], 40, [commodity1, commodity1]
    )
    @test OFOND.lb_transport_units(
        sol, TSGraph, supp1Step2, xdockStep3, order1; use_bins=true, giant=true
    ) ≈ 0.0

    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep3, portStep4], 40, [commodity1, commodity1]
    )
    @test OFOND.lb_transport_units(
        sol, TSGraph, xdockStep3, portStep4, order2; use_bins=true, giant=true
    ) ≈ 1.0
    @test OFOND.lb_transport_units(
        sol, TSGraph, xdockStep3, portStep4, order1; use_bins=false, giant=true
    ) ≈ 1.0
    # direct arc testing case  
    @test OFOND.lb_transport_units(
        sol, TSGraph, supp1Step3, plantStep1, order1; use_bins=false, giant=false
    ) ≈ 1.0
    @test OFOND.lb_transport_units(
        sol, TSGraph, supp1Step3, plantStep1, order1; use_bins=true, giant=true
    ) ≈ 1.0
end

@testset "Arc update cost" begin
    # arc update cost function
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # forbidden arc
    @test OFOND.arc_lb_update_cost(
        sol, TTGraph, TSGraph, bundle1, portFromDel1, plantFromDel0;
    ) ≈ 1e9
    @test OFOND.arc_lb_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        portFromDel1,
        plantFromDel0;
        use_bins=true,
        current_cost=true,
        giant=true,
    ) == 1e9
    # linear arc
    @test OFOND.arc_lb_update_cost(
        sol, TTGraph, TSGraph, bundle1, supp1FromDel3, xdockFromDel2; use_bins=false
    ) ≈ 1e-5 + 1.6 + 0 + 0.004 + 5
    @test OFOND.arc_lb_update_cost(
        sol, TTGraph, TSGraph, bundle1, supp1FromDel3, xdockFromDel2; giant=true
    ) ≈ 1e-5 + 1.6 + 0 + 0.004 + 5
    # consolidated arc with nothing on it
    @test OFOND.arc_lb_update_cost(
        sol, TTGraph, TSGraph, bundle1, xdockFromDel1, plantFromDel0
    ) ≈ 1e-5 + 1.6 + 0 + 0.004 + 5
    @test OFOND.arc_lb_update_cost(
        sol, TTGraph, TSGraph, bundle1, xdockFromDel1, plantFromDel0; giant=true
    ) ≈ 1e-5 + 4 + 0 + 0.004 + 5
    # consolidated arc with things on it
    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep4, plantStep1], 40, [commodity1, commodity1]
    )
    @test OFOND.arc_lb_update_cost(
        sol, TTGraph, TSGraph, bundle1, xdockFromDel1, plantFromDel0; use_bins=false
    ) ≈ 1e-5 + 1.6 + 0 + 0.004 + 5
    TSGraph.currentCost[xdockStep4, plantStep1] = 1.0
    @test OFOND.arc_lb_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        xdockFromDel1,
        plantFromDel0;
        use_bins=false,
        current_cost=true,
        giant=true,
    ) ≈ 1e-5 + 1 + 0 + 0.004 + 5
    @test OFOND.arc_lb_update_cost(
        sol, TTGraph, TSGraph, bundle1, xdockFromDel1, plantFromDel0;
    ) ≈ 1e-5 + 0 + 0 + 0.004 + 5
end

@testset "Cost matrix update" begin
    # update_cost_matrix!
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # empty solution so use bins don't affect but opening factor does
    TTGraph2 = deepcopy(TTGraph)
    OFOND.update_lb_cost_matrix!(sol, TTGraph2, TSGraph, bundle1; use_bins=true)
    TTGraph3 = deepcopy(TTGraph)
    OFOND.update_lb_cost_matrix!(
        sol, TTGraph3, TSGraph, bundle1; use_bins=false, giant=true
    )
    OFOND.update_lb_cost_matrix!(sol, TTGraph, TSGraph, bundle1)
    @test TTGraph.costMatrix == TTGraph2.costMatrix
    # V = vcat(
    #     fill(1e-5 + 6.8, 3), third supp1-xdock starts before supp1 src so stays 1e-5
    #     1e-5,
    #     1e-5 + 110.2, giant(order1) = 1 and unitCost = 10, distance = 2 so 10 for leadTime and 0.2 for carbon
    #     1e-5,
    #     1e-5 + 9.2, giant(order1) = 1 and unitCost = 4 and distance = 1 so 5 for leadTime and 0.2 for carbon
    #     OFOND.INFINITY,
    #     fill(OFOND.INFINITY, 3),
    #     fill(1e-5, 4),
    # )
    V = fill(1e-5, 15)
    V[[1, 2, 5, 7]] .+= [6.604, 6.604, 20.004, 9.004]
    V[8:11] .= 1e9
    @test all([TTGraph3.costMatrix[i, j] for (i, j) in zip(I, J)] .≈ V)

    # add things on some arcs
    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep4, plantStep1], 40, [commodity1, commodity1]
    )
    # use bins affect cost
    OFOND.update_lb_cost_matrix!(sol, TTGraph2, TSGraph, bundle1)
    # V = vcat(
    #     fill(1e-5 + 6.8, 3), third supp1-xdock starts before supp1 src so stays 1e-5
    #     1e-5,
    #     1e-5 + 110.2, linear(order1) = 0.4 but direct so 1 and unitCost = 10, distance = 2 so 10 for leadTime and 0.2 for carbon
    #     1e-5,
    #     1e-5 + 5.2, linear(order1) = 0 (use_bins on) and unitCost = 4 and distance = 1 so 5 for leadTime and 0.2 for carbon
    #     OFOND.INFINITY,
    #     fill(OFOND.INFINITY, 3),
    #     fill(1e-5, 4),
    # )
    V = fill(1e-5, 15)
    V[[1, 2, 5, 7]] .+= [6.604, 6.604, 20.004, 5.004]
    V[8:11] .= 1e9
    @test all([TTGraph2.costMatrix[i, j] for (i, j) in zip(I, J)] .≈ V)
end

@testset "Filtering transport units" begin
    @test OFOND.lb_filtering_transport_units(TSGraph, supp1Step2, xdockStep3, order1) ≈ 0.4
    @test OFOND.lb_filtering_transport_units(TSGraph, supp1Step3, plantStep1, order2) == 3
end

@testset "Filtering arc cost" begin
    # forbidden arc
    @test OFOND.arc_lb_filtering_update_cost(
        TTGraph, TSGraph, bundle1, portFromDel1, plantFromDel0;
    ) ≈ 1e9
    # linear arc
    @test OFOND.arc_lb_filtering_update_cost(
        TTGraph, TSGraph, bundle1, supp1FromDel3, xdockFromDel2
    ) ≈ 1e-5 + 1.6 + 0 + 0.004 + 5
    @test OFOND.arc_lb_filtering_update_cost(
        TTGraph, TSGraph, bundle1, xdockFromDel1, plantFromDel0
    ) ≈ 1e-5 + 1.6 + 0 + 0.004 + 5
    # direct arc (bpDict direct = 3 and distance = 2)
    @test OFOND.arc_lb_filtering_update_cost(
        TTGraph, TSGraph, bundle1, supp1FromDel2, plantFromDel0
    ) ≈ 1e-5 + 3 * 10.0 + 0 + 0.004 + 2 * 5
end

@testset "Filtering cost matrix update" begin
    OFOND.update_lb_filtering_cost_matrix!(TTGraph, TSGraph, bundle1)
    V = fill(1e-5, 15)
    V[[1, 2, 5, 7]] .+= [6.604, 6.604, 40.004, 6.604]
    V[8:11] .= 1e9
    @test all([TTGraph.costMatrix[i, j] for (i, j) in zip(I, J)] .≈ V)
end