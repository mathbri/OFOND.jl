supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
supp1FromDel1 = TTGraph.hashToIdx[hash(1, supplier1.hash)]
supp1FromDel0 = TTGraph.hashToIdx[hash(0, supplier1.hash)]

xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]

portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]

@testset "Update filtering" begin
    # is update candidate function
    @test OFOND.is_update_candidate(TTGraph, supp1FromDel3, xdockFromDel2, bundle1)
    @test OFOND.is_update_candidate(TTGraph, xdockFromDel1, plantFromDel0, bundle1)
    @test !OFOND.is_update_candidate(TTGraph, supp1FromDel3, supp1FromDel2, bundle1)
    # faking bundle1 goes to plant2 
    TTGraph2 = deepcopy(TTGraph)
    TTGraph2.bundleDst[1] = 6
    @test !OFOND.is_update_candidate(TTGraph, xdockFromDel2, plantFromDel0, bundle1)
    # is forbidden function
    @test !OFOND.is_forbidden(TTGraph, xdockFromDel1, plantFromDel0, bundle1)
    @test OFOND.is_forbidden(TTGraph, xdockFromDel2, portFromDel1, bundle1)
    @test OFOND.is_forbidden(TTGraph, portFromDel1, plantFromDel0, bundle1)
end

supp1Step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]

supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
portStep1 = TSGraph.hashToIdx[hash(1, port_l.hash)]
plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]

@testset "Arc order Cost" begin
    # volume stock cost function
    @test OFOND.volume_stock_cost(TTGraph, supp1FromDel3, xdockFromDel2, order1) ≈ 0.2 + 5
    @test OFOND.volume_stock_cost(TTGraph, supp1FromDel3, xdockFromDel2, order2) ≈ 0.3 + 7
    @test OFOND.volume_stock_cost(TTGraph, xdockFromDel1, plantFromDel0, order1) ≈ 0.2 + 5
    @test OFOND.volume_stock_cost(TTGraph, xdockFromDel1, plantFromDel0, order2) ≈ 0.3 + 7
    # transport units 
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    @test OFOND.transport_units(
        sol, TSGraph, supp1Step2, xdockStep3, order1; sorted=true, use_bins=false
    ) ≈ 0.4
    @test OFOND.transport_units(
        sol, TSGraph, supp1Step2, xdockStep3, order2; sorted=true, use_bins=false
    ) ≈ 0.6
    @test OFOND.transport_units(
        sol, TSGraph, xdockStep3, portStep4, order1; sorted=true, use_bins=false
    ) == 2
    @test OFOND.transport_units(
        sol, TSGraph, portStep4, plantStep1, order1; sorted=true, use_bins=false
    ) == 3
    # adding things on the TSGraph to check it is taken into account
    OFOND.first_fit_decreasing!(
        sol.bins[supp1Step2, xdockStep3], 40, [commodity1, commodity1]
    )
    @test OFOND.transport_units(
        sol, TSGraph, supp1Step2, xdockStep3, order1; sorted=true, use_bins=true
    ) ≈ 0.4

    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep3, portStep4], 40, [commodity1, commodity1]
    )
    @test OFOND.transport_units(
        sol, TSGraph, xdockStep3, portStep4, order1; sorted=true, use_bins=true
    ) == 0
    @test OFOND.transport_units(
        sol, TSGraph, xdockStep3, portStep4, order2; sorted=true, use_bins=true
    ) == 1
    @test OFOND.transport_units(
        sol, TSGraph, portStep4, plantStep1, order1; sorted=true, use_bins=true
    ) == 1

    # transport cost
    @test OFOND.transport_cost(TSGraph, portStep4, plantStep1; current_cost=false) ≈ 4.0
    @test OFOND.transport_cost(TSGraph, portStep4, plantStep1; current_cost=true) ≈ 1e-5
    TSGraph[portStep4, plantStep1] = 1.0
    @test OFOND.transport_cost(TSGraph, portStep4, plantStep1; current_cost=true) ≈ 1e-5
end

TTPath = [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]

@testset "Arc bundle cost" begin
    # arc update cost function
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # forbidden arc
    @test OFOND.arc_update_cost(
        sol, TTGraph, TSGraph, bundle1, portFromDel1, plantFromDel0; use_bins=false
    ) == 1e9
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        portFromDel1,
        plantFromDel0;
        sorted=true,
        opening_factor=10.0,
        current_cost=true,
    ) == 1e9
    # linear arc
    @test OFOND.arc_update_cost(
        sol, TTGraph, TSGraph, bundle1, supp1FromDel3, xdockFromDel2; use_bins=false
    ) == 1e-5 + 1.6 + 0 + 0.2 + 5
    @test OFOND.arc_update_cost(
        sol, TTGraph, TSGraph, bundle1, supp1FromDel3, xdockFromDel2; opening_factor=10.0
    ) == 1e-5 + 16 + 0 + 0.2 + 5
    # consolidated arc with nothing on it
    @test OFOND.arc_update_cost(
        sol, TTGraph, TSGraph, bundle1, xdockFromDel1, plantFromDel0; use_bins=false
    ) == 1e-5 + 8 + 0 + 0.2 + 5
    @test OFOND.arc_update_cost(
        sol, TTGraph, TSGraph, bundle1, xdockFromDel1, plantFromDel0; opening_factor=10.0
    ) == 1e-5 + 40 + 0 + 0.2 + 5
    # consolidated arc with things on it
    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep4, plantStep1], 40, [commodity1, commodity1]
    )
    @test OFOND.arc_update_cost(
        sol, TTGraph, TSGraph, bundle1, xdockFromDel1, plantFromDel0; use_bins=false
    ) == 1e-5 + 8 + 0 + 0.2 + 5
    TSGraph.currentCost[portStep4, plantStep1] = 1.0
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        xdockFromDel1,
        plantFromDel0;
        use_bins=false,
        current_cost=true,
    ) == 1e-5 + 2 + 0 + 0.2 + 5
    @test OFOND.arc_update_cost(
        sol, TTGraph, TSGraph, bundle1, xdockFromDel1, plantFromDel0; opening_factor=10.0
    ) == 1e-5 + 0 + 0 + 0.2 + 5
end

@testset "Source nodes finding" begin
    # find_other_src_node
    @test OFOND.find_other_src_node(TTGraph, supp1FromDel3) == supp1FromDel2
    @test OFOND.find_other_src_node(TTGraph, supp1FromDel2) == supp1FromDel1
    @test OFOND.find_other_src_node(TTGraph, supp1FromDel1) == supp1FromDel0
    @test OFOND.find_other_src_node(TTGraph, supp1FromDel0) === nothing
    @test OFOND.find_other_src_node(TTGraph, xdockFromDel2) === nothing
    # get_all_start_nodes
    @test OFOND.get_all_start_nodes(TTGraph, bundle1) ==
        [supp1FromDel2, supp1FromDel1, supp1FromDel0]
    @test OFOND.get_all_start_nodes(TTGraph, bundle2) == [supp2FromDel1, supp2FromDel0]
    @test OFOND.get_all_start_nodes(TTGraph, bundle3) ==
        [supp1FromDel3, supp1FromDel2, supp1FromDel1, supp1FromDel0]
end

I = vcat(
    allIdxs[2:4],
    [allIdxs[6], allIdxs[3], allIdxs[6], allIdxs[8], allIdxs[12]],
    allIdxs[8:10],
    allIdxs[2:4],
    [allIdxs[6]],
)
J = vcat(
    allIdxs[7:9],
    [allIdxs[7], allIdxs[end], allIdxs[end], allIdxs[end], allIdxs[end]],
    allIdxs[11:13],
    allIdxs[1:3],
    [allIdxs[5]],
)

@testset "Cost matrix update" begin
    # update_cost_matrix!
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # empty solution so use bins don't affect but opening factor does
    TTGraph2 = deepcopy(TTGraph)
    OFOND.update_cost_matrix!(sol, TTGraph2, TSGraph, bundle1; use_bins=true)
    TTGraph3 = deepcopy(TTGraph)
    OFOND.update_cost_matrix!(
        sol, TTGraph3, TSGraph, bundle1; use_bins=true, opening_factor=10.0
    )
    OFOND.update_cost_matrix!(sol, TTGraph, TSGraph, bundle1)
    @test TTGraph.costMatrix == TTGraph2.costMatrix
    # V = vcat(
    #     fill(1e-5 + 6.8, 3),
    #     1e-5,
    #     1e-5 + 110.2,
    #     1e-5,
    #     1e-5 + 45.2,
    #     OFOND.INFINITY,
    #     fill(1e-5 + 45, 3),
    #     fill(1e-5, 4),
    # )
    V = fill(1e-5, 15)
    V[[1, 2, 3, 5, 7, 9, 10, 11]] .+= [6.8, 6.8, 6.8, 110.2, 45.2, 45.0, 45.0, 45.0]
    V[8] = 1e9
    @test TTGraph3.costMatrix[I, J] .≈ V

    # add things on some arcs
    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep4, plantStep1], 40, [commodity1, commodity1]
    )
    # use bins affect cost
    OFOND.update_cost_matrix!(sol, TTGraph2, TSGraph, bundle1; use_bins=true)
    V = fill(1e-5, 15)
    V[[1, 2, 3, 5, 7, 9, 10, 11]] .+= [6.8, 6.8, 6.8, 110.2, 0.2, 45.0, 45.0, 45.0]
    V[8] = 1e9
    @test TTGraph2.costMatrix[I, J] .≈ V
end

@testset "Path admissibility and cost" begin
    # is_path_admissible
    @test OFOND.is_path_admissible(TTGraph, TTPath)
    @test !OFOND.is_path_admissible(
        TTGraph, [supp1FromDel3, xdockFromDel2, portFromDel1, xdockFromDel1, plantFromDel0]
    )
    # get_path_cost
    @test OFOND.path_cost(TTPath, TTGraph.costMatrix) ≈ 3e-5
    TTGraph.costMatrix[supp1FromDel3, xdockFromDel2] = 1.0
    @test OFOND.path_cost(TTPath, TTGraph.costMatrix) ≈ 1 + 2e-5
end