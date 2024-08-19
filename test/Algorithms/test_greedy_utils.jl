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
    @test !OFOND.is_update_candidate(TTGraph2, xdockFromDel1, plantFromDel0, bundle1)
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
    @test OFOND.volume_stock_cost(TTGraph, supp1FromDel3, xdockFromDel2, order1) ≈ 0.004 + 5
    @test OFOND.volume_stock_cost(TTGraph, supp1FromDel3, xdockFromDel2, order2) ≈ 0.006 + 7
    @test OFOND.volume_stock_cost(TTGraph, xdockFromDel1, plantFromDel0, order1) ≈ 0.004 + 5
    @test OFOND.volume_stock_cost(TTGraph, xdockFromDel1, plantFromDel0, order2) ≈ 0.006 + 7
    # transport units 
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    @test OFOND.transport_units(
        sol,
        TSGraph,
        supp1Step2,
        xdockStep3,
        order1,
        CAPACITIES;
        sorted=true,
        use_bins=false,
    ) ≈ 0.4
    @test OFOND.transport_units(
        sol,
        TSGraph,
        supp1Step2,
        xdockStep3,
        order2,
        CAPACITIES;
        sorted=true,
        use_bins=false,
    ) ≈ 0.6
    @test OFOND.transport_units(
        sol, TSGraph, xdockStep3, portStep4, order1, CAPACITIES; sorted=true, use_bins=false
    ) == 2
    @test OFOND.transport_units(
        sol,
        TSGraph,
        supp1Step3,
        plantStep1,
        order1,
        CAPACITIES;
        sorted=true,
        use_bins=false,
    ) == 3
    # adding things on the TSGraph to check it is taken into account
    OFOND.first_fit_decreasing!(
        sol.bins[supp1Step2, xdockStep3], 40, [commodity1, commodity1]
    )
    @test OFOND.transport_units(
        sol, TSGraph, supp1Step2, xdockStep3, order1, CAPACITIES; sorted=true, use_bins=true
    ) ≈ 0.4

    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep3, portStep4], 40, [commodity1, commodity1]
    )
    @test OFOND.transport_units(
        sol, TSGraph, xdockStep3, portStep4, order1, CAPACITIES; sorted=true, use_bins=true
    ) == 0
    @test OFOND.transport_units(
        sol, TSGraph, xdockStep3, portStep4, order2, CAPACITIES; sorted=true, use_bins=true
    ) == 1
    # nothing on this arc so tentative_first_fit don't activate
    @test OFOND.transport_units(
        sol, TSGraph, portStep4, plantStep1, order1, CAPACITIES; sorted=true, use_bins=true
    ) == 2

    # transport cost
    @test OFOND.transport_cost(TSGraph, portStep4, plantStep1; current_cost=false) ≈ 4.0
    @test OFOND.transport_cost(TSGraph, portStep4, plantStep1; current_cost=true) ≈ 1e-5
    TSGraph.currentCost[portStep4, plantStep1] = 1.0
    @test OFOND.transport_cost(TSGraph, portStep4, plantStep1; current_cost=true) ≈ 1.0
end

TTPath = [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]

@testset "Arc bundle cost" begin
    # arc update cost function
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # forbidden arc
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        portFromDel1,
        plantFromDel0,
        CAPACITIES;
        use_bins=false,
    ) ≈ 1e9
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        portFromDel1,
        plantFromDel0,
        CAPACITIES;
        sorted=true,
        opening_factor=10.0,
        current_cost=true,
    ) ≈ 1e9
    # linear arc
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        supp1FromDel3,
        xdockFromDel2,
        CAPACITIES;
        use_bins=false,
    ) ≈ 1e-5 + 1.6 + 0 + 0.004 + 5
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        supp1FromDel3,
        xdockFromDel2,
        CAPACITIES;
        opening_factor=10.0,
    ) ≈ 1e-5 + 16 + 0 + 0.004 + 5
    # consolidated arc with nothing on it (tentaive first fit shouldn't activate)
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        xdockFromDel1,
        plantFromDel0,
        CAPACITIES;
        use_bins=false,
    ) ≈ 1e-5 + 8 + 0 + 0.004 + 5
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        xdockFromDel1,
        plantFromDel0,
        CAPACITIES;
        opening_factor=10.0,
    ) ≈ 1e-5 + 80 + 0 + 0.004 + 5
    # consolidated arc with things on it
    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep4, plantStep1], 40, [commodity1, commodity1]
    )
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        xdockFromDel1,
        plantFromDel0,
        CAPACITIES;
        use_bins=false,
    ) ≈ 1e-5 + 8 + 0 + 0.004 + 5
    TSGraph.currentCost[xdockStep4, plantStep1] = 1.0
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        xdockFromDel1,
        plantFromDel0,
        CAPACITIES;
        use_bins=false,
        current_cost=true,
    ) ≈ 1e-5 + 2 + 0 + 0.004 + 5
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        xdockFromDel1,
        plantFromDel0,
        CAPACITIES;
        opening_factor=10.0,
    ) ≈ 1e-5 + 0 + 0 + 0.004 + 5
end

@testset "Source nodes finding" begin
    supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
    supp2FromDel0 = TTGraph.hashToIdx[hash(0, supplier2.hash)]
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
    allTTIdxs[2:4],
    [allTTIdxs[6], allTTIdxs[3], allTTIdxs[6], allTTIdxs[8], allTTIdxs[12]],
    allTTIdxs[8:10],
    allTTIdxs[2:4],
    [allTTIdxs[6]],
)
J = vcat(
    allTTIdxs[7:9],
    [allTTIdxs[7], allTTIdxs[end], allTTIdxs[end], allTTIdxs[end], allTTIdxs[end]],
    allTTIdxs[11:13],
    allTTIdxs[1:3],
    [allTTIdxs[5]],
)

@testset "Cost matrix update" begin
    # update_cost_matrix!
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # empty solution so use bins don't affect but opening factor does
    TTGraph2 = deepcopy(TTGraph)
    OFOND.update_cost_matrix!(sol, TTGraph2, TSGraph, bundle1, CAPACITIES; use_bins=true)
    TTGraph3 = deepcopy(TTGraph)
    OFOND.update_cost_matrix!(
        sol, TTGraph3, TSGraph, bundle1, CAPACITIES; use_bins=true, opening_factor=10.0
    )
    OFOND.update_cost_matrix!(sol, TTGraph, TSGraph, bundle1, CAPACITIES)
    @test TTGraph.costMatrix == TTGraph2.costMatrix
    # V = vcat(
    #     fill(1e-5 + 16 + 5.2, 3), third supp1-xdock starts before supp1 src so stays 1e-5
    #     1e-5,
    #     1e-5 + 310.2, bpUnits[:direct] = 3 and unitCost * openingFactor = 100
    #     1e-5,
    #     1e-5 + 85.2, bpUnits[:delivery] = 2 and unitCost * openingFactor = 40
    #     OFOND.INFINITY,
    #     fill(OFOND.INFINITY, 3),
    #     fill(1e-5, 4),
    # )
    V = fill(1e-5, 15)
    V[[1, 2, 5, 7]] .+= [21.004, 21.004, 310.004, 85.004]
    V[8:11] .= 1e9
    @test all([TTGraph3.costMatrix[i, j] for (i, j) in zip(I, J)] .≈ V)

    # add things on some arcs
    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep4, plantStep1], 40, [commodity1, commodity1]
    )
    # use bins affect cost
    OFOND.update_cost_matrix!(sol, TTGraph2, TSGraph, bundle1, CAPACITIES; use_bins=true)
    # V = vcat(
    #     fill(1e-5 + 6.8, 3), third supp1-xdock starts before supp1 src so stays 1e-5
    #     1e-5,
    #     1e-5 + 40.2, bpUnits[:direct] = 3 and unitCost = 10 and distance = 2 so 10 for leadTime and 0.2 for carbon
    #     1e-5,
    #     1e-5 + 85.2, FFD(delivery) = 0 (bin alreday there) and unitCost = 4 and distance = 1 so 5 for leadTime and 0.2 for carbon
    #     OFOND.INFINITY,
    #     fill(OFOND.INFINITY, 3),
    #     fill(1e-5, 4),
    # )
    V = fill(1e-5, 15)
    V[[1, 2, 5, 7]] .+= [6.604, 6.604, 40.004, 5.004]
    V[8:11] .= 1e9
    @test all([TTGraph2.costMatrix[i, j] for (i, j) in zip(I, J)] .≈ V)
end

@testset "Path admissibility and cost" begin
    # is_path_admissible
    @test OFOND.is_path_admissible(TTGraph, TTPath)
    @test !OFOND.is_path_admissible(
        TTGraph, [supp1FromDel3, xdockFromDel2, portFromDel1, xdockFromDel1, plantFromDel0]
    )
    # get_path_cost
    TTGraph.costMatrix[supp1FromDel3, xdockFromDel2] = 1.0
    TTGraph.costMatrix[xdockFromDel2, portFromDel1] = 1.5
    TTGraph.costMatrix[portFromDel1, plantFromDel0] = 2.1
    @test OFOND.path_cost(TTPath, TTGraph.costMatrix) ≈ 4.6
    TTGraph.costMatrix[supp1FromDel3, xdockFromDel2] = 10.0
    @test OFOND.path_cost(TTPath, TTGraph.costMatrix) ≈ 13.6
end