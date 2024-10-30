supp1Step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]

@testset "Transport units" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    @test OFOND.lb_transport_units(
        sol, TSGraph, supp1Step2, xdockStep3, order11; use_bins=false, giant=false
    ) ≈ 0.4
    @test OFOND.lb_transport_units(
        sol, TSGraph, supp1Step2, xdockStep3, order22; use_bins=false, giant=true
    ) ≈ 0.6
    @test OFOND.lb_transport_units(
        sol, TSGraph, xdockStep3, portStep4, order11; use_bins=false, giant=false
    ) ≈ 0.4
    @test OFOND.lb_transport_units(
        sol, TSGraph, portStep4, plantStep1, order11; use_bins=false, giant=true
    ) ≈ 1.0
    # adding things on the TSGraph to check it is taken into account
    OFOND.first_fit_decreasing!(
        sol.bins[supp1Step2, xdockStep3], 40, [commodity1, commodity1]
    )
    @test OFOND.lb_transport_units(
        sol, TSGraph, supp1Step2, xdockStep3, order11; use_bins=true, giant=true
    ) ≈ 0.0

    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep3, portStep4], 40, [commodity1, commodity1]
    )
    @test OFOND.lb_transport_units(
        sol, TSGraph, xdockStep3, portStep4, order22; use_bins=true, giant=true
    ) ≈ 1.0
    @test OFOND.lb_transport_units(
        sol, TSGraph, xdockStep3, portStep4, order11; use_bins=false, giant=true
    ) ≈ 1.0
    # direct arc testing case  
    @test OFOND.lb_transport_units(
        sol, TSGraph, supp1Step3, plantStep1, order11; use_bins=false, giant=false
    ) ≈ 1.0
    @test OFOND.lb_transport_units(
        sol, TSGraph, supp1Step3, plantStep1, order11; use_bins=true, giant=true
    ) ≈ 1.0
end

portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]

xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]

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
        sol, TTGraph, TSGraph, bundle11, supp1FromDel3, xdockFromDel2; use_bins=false
    ) ≈ 1e-5 + 1.6 + 0 + 0.2 + 5
    @test OFOND.arc_lb_update_cost(
        sol, TTGraph, TSGraph, bundle11, supp1FromDel3, xdockFromDel2; giant=true
    ) ≈ 1e-5 + 1.6 + 0 + 0.2 + 5
    # consolidated arc with nothing on it
    @test OFOND.arc_lb_update_cost(
        sol, TTGraph, TSGraph, bundle11, xdockFromDel1, plantFromDel0
    ) ≈ 1e-5 + 1.6 + 0 + 0.4 + 5
    @test OFOND.arc_lb_update_cost(
        sol, TTGraph, TSGraph, bundle11, xdockFromDel1, plantFromDel0; giant=true
    ) ≈ 1e-5 + 4 + 0 + 0.4 + 5
    # consolidated arc with things on it
    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep4, plantStep1], 40, [commodity1, commodity1]
    )
    @test OFOND.arc_lb_update_cost(
        sol, TTGraph, TSGraph, bundle11, xdockFromDel1, plantFromDel0; use_bins=false
    ) ≈ 1e-5 + 1.6 + 0 + 0.4 + 5
    TSGraph.currentCost[xdockStep4, plantStep1] = 1.0
    @test OFOND.arc_lb_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle11,
        xdockFromDel1,
        plantFromDel0;
        use_bins=false,
        current_cost=true,
        giant=true,
    ) ≈ 1e-5 + 1 + 0 + 0.4 + 5
    @test OFOND.arc_lb_update_cost(
        sol, TTGraph, TSGraph, bundle11, xdockFromDel1, plantFromDel0;
    ) ≈ 1e-5 + 0 + 0 + 0.4 + 5
end

supp1FromDel1 = TTGraph.hashToIdx[hash(1, supplier1.hash)]
supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
supp2FromDel2 = TTGraph.hashToIdx[hash(2, supplier2.hash)]
supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
supp3FromDel3 = TTGraph.hashToIdx[hash(3, supplier3.hash)]
supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]
supp3FromDel1 = TTGraph.hashToIdx[hash(1, supplier3.hash)]
xdockFromDel3 = TTGraph.hashToIdx[hash(3, xdock.hash)]
supp1FromDel0 = TTGraph.hashToIdx[hash(0, supplier1.hash)]
supp2FromDel0 = TTGraph.hashToIdx[hash(0, supplier2.hash)]
supp3FromDel0 = TTGraph.hashToIdx[hash(0, supplier3.hash)]
xdockFromDel0 = TTGraph.hashToIdx[hash(0, xdock.hash)]
portFromDel0 = TTGraph.hashToIdx[hash(0, port_l.hash)]
portFromDel2 = TTGraph.hashToIdx[hash(2, port_l.hash)]

I = vcat(
    # shortcuts
    [supp1FromDel3, supp1FromDel2, supp1FromDel1],
    [supp2FromDel2, supp2FromDel1],
    [supp3FromDel3, supp3FromDel2, supp3FromDel1],
    # oursource
    [supp1FromDel3, supp1FromDel2, supp1FromDel1],
    [supp2FromDel2, supp2FromDel1],
    [supp3FromDel3, supp3FromDel2, supp3FromDel1],
    # directs
    [supp1FromDel2, supp2FromDel1, supp3FromDel2],
    # xdock - port 
    [xdockFromDel3, xdockFromDel2, xdockFromDel1],
    # xdock -plant and port - plant
    [xdockFromDel1, portFromDel1],
)
J = vcat(
    # shortcuts
    [supp1FromDel2, supp1FromDel1, supp1FromDel0],
    [supp2FromDel1, supp2FromDel0],
    [supp3FromDel2, supp3FromDel1, supp3FromDel0],
    # oursource
    [xdockFromDel2, xdockFromDel1, xdockFromDel0],
    [xdockFromDel1, xdockFromDel0],
    [xdockFromDel2, xdockFromDel1, xdockFromDel0],
    # directs
    [plantFromDel0, plantFromDel0, plantFromDel0],
    # xdock - port
    [portFromDel2, portFromDel1, portFromDel0],
    # xdock - plant and port - plant
    [plantFromDel0, plantFromDel0],
)
V = fill(1e-5, 24)

@testset "Cost matrix update" begin
    # update_cost_matrix!
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # empty solution so use bins don't affect but opening factor does
    TTGraph2 = deepcopy(TTGraph)
    OFOND.update_lb_cost_matrix!(sol, TTGraph2, TSGraph, bundle11; use_bins=true)
    TTGraph3 = deepcopy(TTGraph)
    OFOND.update_lb_cost_matrix!(
        sol, TTGraph3, TSGraph, bundle11; use_bins=false, giant=true
    )
    OFOND.update_lb_cost_matrix!(sol, TTGraph, TSGraph, bundle11)
    @test TTGraph.costMatrix == TTGraph2.costMatrix
    # Outsource cost (just for bundle 1, bundle 2 and 2 are not concerned)
    V[9:16] .+= [6.8, 6.8, 6.8, 0.0, 0.0, 0.0, 0.0, 0.0]
    # Direct costs (just for bundle 1)
    V[17:19] .+= [20.4, 0.0, 0.0]
    # Xdock-port costs (forbidden arcs)
    V[20:22] .= 1e9
    # Delivery costs
    V[23:24] .+= [9.4, 1.0e9]
    costs = sparse(I, J, V)
    @testset "Cost for arc $i-$j" for (i, j) in zip(I, J)
        @test TTGraph3.costMatrix[i, j] ≈ costs[i, j]
    end

    V[1:end] = fill(1e-5, 24)

    # add things on some arcs
    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep4, plantStep1], 40, [commodity1, commodity1]
    )
    # use bins affect cost
    OFOND.update_lb_cost_matrix!(sol, TTGraph2, TSGraph, bundle11)
    # Outsource cost (just for bundle 1, bundle 2 and 2 are not concerned)
    V[9:16] .+= [6.8, 6.8, 6.8, 0.0, 0.0, 0.0, 0.0, 0.0]
    # Direct costs (just for bundle 1)
    V[17:19] .+= [20.4, 0.0, 0.0]
    # Xdock-port costs (forbidden arcs)
    V[20:22] .= 1e9
    # Delivery costs
    V[23:24] .+= [5.4, 1.0e9]
    costs = sparse(I, J, V)
    @testset "Cost for arc $i-$j" for (i, j) in zip(I, J)
        @test TTGraph2.costMatrix[i, j] ≈ costs[i, j]
    end
end

@testset "Filtering transport units" begin
    @test OFOND.lb_filtering_transport_units(TSGraph, supp1Step2, xdockStep3, order11) ≈ 0.4
    @test OFOND.lb_filtering_transport_units(TSGraph, supp1Step3, plantStep1, order22) == 2
end

@testset "Filtering arc cost" begin
    # forbidden arc
    @test OFOND.arc_lb_filtering_update_cost(
        TTGraph, TSGraph, bundle11, portFromDel1, plantFromDel0;
    ) ≈ 1e9
    # linear arc
    @test OFOND.arc_lb_filtering_update_cost(
        TTGraph, TSGraph, bundle11, supp1FromDel3, xdockFromDel2
    ) ≈ 1e-5 + 1.6 + 0 + 0.2 + 5
    @test OFOND.arc_lb_filtering_update_cost(
        TTGraph, TSGraph, bundle11, xdockFromDel1, plantFromDel0
    ) ≈ 1e-5 + 1.6 + 0 + 0.4 + 5
    # direct arc (bpDict direct = 3 and distance = 2)
    @test OFOND.arc_lb_filtering_update_cost(
        TTGraph, TSGraph, bundle11, supp1FromDel2, plantFromDel0
    ) ≈ 1e-5 + 2 * 10.0 + 0 + 0.4 + 2 * 5
end

@testset "Filtering cost matrix update" begin
    V[1:end] = fill(1e-5, 24)
    # use bins affect cost
    OFOND.update_lb_filtering_cost_matrix!(TTGraph, TSGraph, bundle11)
    # Outsource cost (just for bundle 1, bundle 2 and 2 are not concerned)
    V[9:16] .+= [6.8, 6.8, 6.8, 0.0, 0.0, 0.0, 0.0, 0.0]
    # Direct costs (just for bundle 1)
    V[17:19] .+= [30.4, 0.0, 0.0]
    # Xdock-port costs (forbidden arcs)
    V[20:22] .= 1e9
    # Delivery costs
    V[23:24] .+= [7.0, 1.0e9]
    costs = sparse(I, J, V)
    @testset "Cost for arc $i-$j" for (i, j) in zip(I, J)
        @test TTGraph.costMatrix[i, j] ≈ costs[i, j]
    end
end