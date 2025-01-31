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
    # 5 for stock + 20 / 100 * 1 for platform + 20 / 50 * 0 for carbon
    @test OFOND.volume_stock_cost(TTGraph, supp1FromDel3, xdockFromDel2, order11) ≈ 0.2 + 5
    @test OFOND.volume_stock_cost(TTGraph, supp1FromDel3, xdockFromDel2, order22) ≈ 0.3 + 7
    @test OFOND.volume_stock_cost(TTGraph, xdockFromDel1, plantFromDel0, order11) ≈ 0.4 + 5
    @test OFOND.volume_stock_cost(TTGraph, xdockFromDel1, plantFromDel0, order22) ≈ 0.6 + 7
    # transport units 
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    @test OFOND.transport_units(
        sol,
        TSGraph,
        supp1Step2,
        xdockStep3,
        order11,
        CAPACITIES;
        sorted=true,
        use_bins=false,
    ) ≈ 0.4
    @test OFOND.transport_units(
        sol,
        TSGraph,
        supp1Step2,
        xdockStep3,
        order22,
        CAPACITIES;
        sorted=true,
        use_bins=false,
    ) ≈ 0.6
    @test OFOND.transport_units(
        sol,
        TSGraph,
        xdockStep3,
        portStep4,
        order11,
        CAPACITIES;
        sorted=true,
        use_bins=false,
    ) == 2
    @test OFOND.transport_units(
        sol,
        TSGraph,
        supp1Step3,
        plantStep1,
        order11,
        CAPACITIES;
        sorted=true,
        use_bins=false,
    ) == 2
    # adding things on the TSGraph to check it is taken into account
    OFOND.first_fit_decreasing!(
        sol.bins[supp1Step2, xdockStep3], 40, [commodity1, commodity1]
    )
    @test OFOND.transport_units(
        sol,
        TSGraph,
        supp1Step2,
        xdockStep3,
        order11,
        CAPACITIES;
        sorted=true,
        use_bins=true,
    ) ≈ 0.4

    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep3, portStep4], 40, [commodity1, commodity1]
    )
    @test OFOND.transport_units(
        sol, TSGraph, xdockStep3, portStep4, order11, CAPACITIES; sorted=true, use_bins=true
    ) == 0
    @test OFOND.transport_units(
        sol, TSGraph, xdockStep3, portStep4, order22, CAPACITIES; sorted=true, use_bins=true
    ) == 1
    # nothing on this arc so tentative_first_fit don't activate
    @test OFOND.transport_units(
        sol, TSGraph, portStep4, plantStep1, order11, CAPACITIES; sorted=true, use_bins=true
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
    ) ≈ 1e-5
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle11,
        portFromDel1,
        plantFromDel0,
        CAPACITIES;
        sorted=true,
        opening_factor=10.0,
        current_cost=true,
    ) ≈ 25.4 + 1e-5
    # linear arc : base + transport + carbon + platform + stock costs
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle11,
        supp1FromDel3,
        xdockFromDel2,
        CAPACITIES;
        use_bins=false,
    ) ≈ 1e-5 + 1.6 + 0 + 0.2 + 5
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle11,
        supp1FromDel3,
        xdockFromDel2,
        CAPACITIES;
        opening_factor=10.0,
    ) ≈ 1e-5 + 16 + 0 + 0.2 + 5
    # consolidated arc with nothing on it (tentaive first fit shouldn't activate)
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle11,
        xdockFromDel1,
        plantFromDel0,
        CAPACITIES;
        use_bins=false,
    ) ≈ 1e-5 + 8 + 0 + 0.4 + 5
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle11,
        xdockFromDel1,
        plantFromDel0,
        CAPACITIES;
        opening_factor=10.0,
    ) ≈ 1e-5 + 80 + 0 + 0.4 + 5
    # consolidated arc with things on it
    OFOND.first_fit_decreasing!(
        sol.bins[xdockStep4, plantStep1], 40, [commodity1, commodity1]
    )
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle11,
        xdockFromDel1,
        plantFromDel0,
        CAPACITIES;
        use_bins=false,
    ) ≈ 1e-5 + 8 + 0 + 0.4 + 5
    TSGraph.currentCost[xdockStep4, plantStep1] = 1.0
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle11,
        xdockFromDel1,
        plantFromDel0,
        CAPACITIES;
        use_bins=false,
        current_cost=true,
    ) ≈ 1e-5 + 2 + 0 + 0.4 + 5
    @test OFOND.arc_update_cost(
        sol,
        TTGraph,
        TSGraph,
        bundle11,
        xdockFromDel1,
        plantFromDel0,
        CAPACITIES;
        opening_factor=10.0,
    ) ≈ 1e-5 + 0 + 0 + 0.4 + 5
end

supp2FromDel2 = TTGraph.hashToIdx[hash(2, supplier2.hash)]
supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
supp2FromDel0 = TTGraph.hashToIdx[hash(0, supplier2.hash)]

supp3FromDel0 = TTGraph.hashToIdx[hash(0, supplier3.hash)]
supp3FromDel1 = TTGraph.hashToIdx[hash(1, supplier3.hash)]
supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]
supp3FromDel3 = TTGraph.hashToIdx[hash(3, supplier3.hash)]

@testset "Source nodes finding" begin
    # find_other_src_node
    @test OFOND.find_other_src_node(TTGraph, supp1FromDel3) == supp1FromDel2
    @test OFOND.find_other_src_node(TTGraph, supp1FromDel2) == supp1FromDel1
    @test OFOND.find_other_src_node(TTGraph, supp1FromDel1) == supp1FromDel0
    @test OFOND.find_other_src_node(TTGraph, supp1FromDel0) == -1
    @test OFOND.find_other_src_node(TTGraph, xdockFromDel2) == -1
    # get_all_start_nodes
    @test OFOND.get_all_start_nodes(TTGraph, bundle1) ==
        [supp1FromDel3, supp1FromDel2, supp1FromDel1, supp1FromDel0]
    @test OFOND.get_all_start_nodes(TTGraph, bundle2) ==
        [supp2FromDel2, supp2FromDel1, supp2FromDel0]
    @test OFOND.get_all_start_nodes(TTGraph, bundle3) ==
        [supp3FromDel3, supp3FromDel2, supp3FromDel1, supp3FromDel0]
end

xdockFromDel3 = TTGraph.hashToIdx[hash(3, xdock.hash)]
portFromDel2 = TTGraph.hashToIdx[hash(2, port_l.hash)]
portFromDel0 = TTGraph.hashToIdx[hash(0, port_l.hash)]
supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
xdockFromDel0 = TTGraph.hashToIdx[hash(0, xdock.hash)]

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
    OFOND.update_cost_matrix!(sol, TTGraph2, TSGraph, bundle11, CAPACITIES; use_bins=true)
    TTGraph3 = deepcopy(TTGraph)
    OFOND.update_cost_matrix!(
        sol, TTGraph3, TSGraph, bundle11, CAPACITIES; use_bins=true, opening_factor=10.0
    )
    OFOND.update_cost_matrix!(sol, TTGraph, TSGraph, bundle11, CAPACITIES)
    @test TTGraph.costMatrix == TTGraph2.costMatrix
    # Outsource cost (just for bundle 1, bundle 2 and 2 are not concerned)
    V[9:16] .+= [21.2, 21.2, 21.2, 0.0, 0.0, 0.0, 0.0, 0.0]
    # Direct costs (just for bundle 1)
    V[17:19] .+= [210.4, 0.0, 0.0]
    # Xdock-port costs (forbidden arcs)
    V[20:22] .+= 85
    # Delivery costs
    V[23:24] .+= 85.4
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
    OFOND.update_cost_matrix!(sol, TTGraph2, TSGraph, bundle11, CAPACITIES; use_bins=true)
    # Outsource cost (just for bundle 1, bundle 2 and 2 are not concerned)
    V[9:16] .+= [6.8, 6.8, 6.8, 0.0, 0.0, 0.0, 0.0, 0.0]
    # Direct costs (just for bundle 1)
    V[17:19] .+= [30.4, 0.0, 0.0]
    # Xdock-port costs (forbidden arcs)
    V[20:22] .+= 13
    # Delivery costs
    V[23:24] .+= [5.4, 13.4]
    costs = sparse(I, J, V)
    @testset "Cost for arc $i-$j" for (i, j) in zip(I, J)
        @test TTGraph2.costMatrix[i, j] ≈ costs[i, j]
    end
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

@testset "Cost matrix parallel update" begin
    # Testing channel creation
    chnl = OFOND.create_channel(Vector{Int}; n=4)
    # println("before length Test")
    @test Base.n_avail(chnl) == 4
    # println("before content test")
    @testset "Channel content test" for _ in 1:4
        content = take!(chnl)
        @test content == Int[]
    end
    @test Base.n_avail(chnl) == 0
    Base.close(chnl)

    # Creating channel again because you can't iterate over it twice but use take! and put! indefinitely
    # println("before channel creation again")
    chnl = OFOND.create_channel(Vector{Int})
    # println("after channel creation again")
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    newTTGraph = OFOND.TravelTimeGraph(network, bundles)
    # add things on some arcs
    push!(sol.bins[xdockStep4, plantStep1], OFOND.Bin(30, 20, [commodity1, commodity1]))
    push!(sol.bins[xdockStep4, plantStep1], OFOND.Bin(30, 20, [commodity1, commodity1]))
    arcCosts = Float64[]
    OFOND.parallel_update_cost_matrix!(sol, newTTGraph, TSGraph, bundle11, chnl, arcCosts)
    V[1:end] = fill(1e-5, 24)
    # Outsource cost (just for bundle 1 on its two first time steps, bundle 2 and 2 are not concerned)
    V[9:16] .+= [6.8, 6.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    # Direct costs (just for bundle 1)
    V[17:19] .+= [30.4, 0.0, 0.0]
    # Xdock-port costs (forbidden arcs)
    V[20:22] .+= [0.0, 13, 0.0]
    # Delivery costs
    V[23:24] .+= [5.4, 13.4]
    costs = sparse(I, J, V)
    @testset "Cost for arc $i-$j" for (i, j) in zip(I, J)
        @test newTTGraph.costMatrix[i, j] ≈ costs[i, j]
    end

    # Testing channel and arcCosts modification
    @test Base.n_avail(chnl) == 8
    # @test !all(buffer == Int[] for buffer in chnl)
    # for i in 1:8
    #     buffer = take!(chnl)
    #     println("Buffer $i : ", buffer)
    #     put!(chnl, buffer)
    # end
    # println(newTTGraph.bundleArcs[1])
    @test all(arcCosts .≈ (1e-5 .+ [6.8, 30.4, 0.0, 6.8, 5.4, 13, 13.4]))
    # println()

    # Testing computation in series using the same channel
    OFOND.parallel_update_cost_matrix!(sol, newTTGraph, TSGraph, bundle22, chnl, arcCosts)
    V[1:end] .= 1e-5
    # Outsource cost (just for bundle 1 on its two first time steps, bundle 2 on its first and 2 are not concerned)
    V[9:16] .+= [6.8, 6.8, 0.0, 7 + 30 * (4 / 51 + 1 / 100), 0.0, 0.0, 0.0, 0.0]
    # Direct costs (just for bundle 1 and 2)
    V[17:19] .+= [30.4, 20 + 14 + 30 / 51, 0.0]
    # Xdock-port costs (forbidden arcs)
    V[20:22] .+= [0.0, 13, 0.0]
    # Delivery costs for bundle 2 changed in comparison to bundle 1
    V[23:24] .+= [7.6, 13.4]
    costs = sparse(I, J, V)
    @testset "Cost for arc $i-$j" for (i, j) in zip(I, J)
        @test newTTGraph.costMatrix[i, j] ≈ costs[i, j]
    end

    # for i in 1:8
    #     buffer = take!(chnl)
    #     println("Buffer $i : ", buffer)
    #     put!(chnl, buffer)
    # end
    # First part is like for bundle 2 and last part are reminiscence of bundle 1
    # println(newTTGraph.bundleArcs[2])
    @test all(
        arcCosts .≈
        (1e-5 .+ [20 + 14 + 30 / 51, 0.0, 7 + 30 * (4 / 51 + 1 / 100), 7.6, 5.4, 13, 13.4]),
    )
    close(chnl)
end

@testset "Cost matrix parallel update 2" begin
    # Creating channel again because you can't iterate over it twice but use take! and put! indefinitely
    chnl = OFOND.create_channel(Vector{Int})
    # println("after channel creation again")
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    newTTGraph = OFOND.TravelTimeGraph(network, bundles)
    # add things on some arcs
    push!(sol.bins[xdockStep4, plantStep1], OFOND.Bin(30, 20, [commodity1, commodity1]))
    push!(sol.bins[xdockStep4, plantStep1], OFOND.Bin(30, 20, [commodity1, commodity1]))
    OFOND.parallel_update_cost_matrix2!(sol, newTTGraph, TSGraph, bundle11, chnl)
    V[1:end] = fill(1e-5, 24)
    # Outsource cost (just for bundle 1 on its two first time steps, bundle 2 and 2 are not concerned)
    V[9:16] .+= [6.8, 6.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    # Direct costs (just for bundle 1)
    V[17:19] .+= [30.4, 0.0, 0.0]
    # Xdock-port costs (forbidden arcs)
    V[20:22] .+= [0.0, 13, 0.0]
    # Delivery costs
    V[23:24] .+= [5.4, 13.4]
    costs = sparse(I, J, V)
    @testset "Cost for arc $i-$j" for (i, j) in zip(I, J)
        @test newTTGraph.costMatrix[i, j] ≈ costs[i, j]
    end

    # Testing computation in series using the same channel
    OFOND.parallel_update_cost_matrix2!(sol, newTTGraph, TSGraph, bundle22, chnl)
    V[1:end] .= 1e-5
    # Outsource cost (just for bundle 1 on its two first time steps, bundle 2 on its first and 2 are not concerned)
    V[9:16] .+= [6.8, 6.8, 0.0, 7 + 30 * (4 / 51 + 1 / 100), 0.0, 0.0, 0.0, 0.0]
    # Direct costs (just for bundle 1 and 2)
    V[17:19] .+= [30.4, 20 + 14 + 30 / 51, 0.0]
    # Xdock-port costs (forbidden arcs)
    V[20:22] .+= [0.0, 13, 0.0]
    # Delivery costs for bundle 2 changed in comparison to bundle 1
    V[23:24] .+= [7.6, 13.4]
    costs = sparse(I, J, V)
    @testset "Cost for arc $i-$j" for (i, j) in zip(I, J)
        @test newTTGraph.costMatrix[i, j] ≈ costs[i, j]
    end

    close(chnl)
end