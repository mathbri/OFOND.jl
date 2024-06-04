supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]

@testset "Lower bound path" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # classic path computation
    path, cost = OFOND.lower_bound_path(
        sol, TTGraph, TSGraph, bundle1, supp1FromDel2, plantFromDel0
    )
    @test path == [supp1FromDel2, plantFromDel0]
    @test cost ≈ 20.2
    # change bins to change path 
    push!(sol.bins[xdockStep4, plantStep1], OFOND.Bin(50))
    path, cost = OFOND.lower_bound_path(
        sol, TTGraph, TSGraph, bundle1, supp1FromDel2, plantFromDel0; use_bins=true
    )
    @test path == [supp1FromDel2, xdockFromDel1, plantFromDel0]
    @test cost ≈ 20.2
    # change current cost to change path 
    empty!(sol.bins[xdockStep4, plantStep1])
    TSGraph.currentCost[xdockStep4, plantStep1] = 1.0
    path, cost = OFOND.lower_bound_path(
        sol, TTGraph, TSGraph, bundle1, supp1FromDel2, plantFromDel0; current_cost=true
    )
    @test path == [supp1FromDel2, xdockFromDel1, plantFromDel0]
    @test cost ≈ 20.2
end

# TODO : adapt this function below

# Modifying instance a little for testing
# Adding a cycle in the network that won't be one in the time expansion
network2 = deepcopy(network)
supplier3 = OFOND.NetworkNode("003", :supplier, "Supp3", LLA(1, 1), "CN", "AS", false, 0.0)
OFOND.add_node!(network2, supplier3)
port_to_xdock = OFOND.NetworkArc(:cross_plat, 1.0, 0, true, 4.0, false, 0.0, 50)
OFOND.add_arc!(network2, port_l, xdock, port_to_xdock)
OFOND.add_arc!(network2, supplier3, xdock, supp_to_plat)
# Adding another bundle
bunH3 = hash(supplier3, hash(plant))
bundle4 = OFOND.Bundle(supplier3, plant, [order3], 1, bunH3, 10, 3)
# Cretaing new instance
TTGraph2 = OFOND.TravelTimeGraph(network2, [bundle4])
TSGraph2 = OFOND.TimeSpaceGraph(network2, 4)
instance2 = OFOND.Instance(network2, TTGraph2, TSGraph2, [bundle4], 4, dates)

@testset "Lower bound insertion" begin
    sol2 = OFOND.Solution(TTGraph2, TSGraph2, [bundle4])
    supp3Idx = TTGraph2.hashToIdx[hash(3, supplier3.hash)]
    plantIdx = TTGraph2.hashToIdx[hash(0, plant.hash)]
    # get 3 paths 
    # one directly admissible (classic one)
    path1, cost1 = OFOND.lower_bound_insertion(
        sol2, TTGraph2, TSGraph2, bundle4, supp3Idx, plantIdx
    )
    @test path1 == [supp3FromDel2, xdockFromDel1, plantFromDel0]
    @test cost1 ≈ 20.2
    @test OFOND.is_path_admissible(TTGraph2, path1)
    # one admissible only with half opening cost : pain in the ass
    # TODO
    # path1, cost1 = OFOND.greedy_insertion(
    #     sol2, TTGraph2, TSGraph2, bundle4, supp3Idx, plantIdx
    # )
    # one neither : change scale of others to force the path
    TSGraph2.currentCost .*= 10
    I = [xdockStep3, supp3step2, portStep4]
    J = [portStep4, xdockStep3, xdockStep4]
    TSGraph2.currentCost[I, J] .*= 0.1
    # path2 should not be admissible
    path2, cost2 = OFOND.lower_bound_path(
        sol2, TTGraph2, TSGraph2, bundle4, supp3Idx, plantIdx; current_cost=true
    )
    @test path2 ==
        [supp3FromDel3, xdockFromDel2, portFromDel2, xdockFromDel1, plantFromDel0]
    @test cost2 ≈ 1e-4 + 3e-5
    @test !OFOND.is_path_admissible(TTGraph2, path1)
    # path3 should and be equal to path1
    path3, cost3 = OFOND.lower_bound_insertion(
        sol2, TTGraph2, TSGraph2, bundle4, supp3Idx, plantIdx; current_cost=true
    )
    @test path3 == path1
    @test cost3 ≈ 2e-5
    @test OFOND.is_path_admissible(TTGraph2, path1)
end

supp2fromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]

@testset "Heuristic" begin
    # run heuristic and test solution as for benchmark
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    lowerBound = OFOND.lower_bound!(sol, instance)
    @test sol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2fromDel1, plantFromDel0],
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
    ]
    filteredBundleOnNode = filter(p -> length(p.second) > 0, sol.bundlesOnNode)
    @test filteredBundleOnNode == [
        xdockFromDel1 => [bundle1, bundle3], plantFromDel0 => [bundle1, bundle2, bundle3]
    ]
    @test sol.bins[supp1Step3, xdockStep4] ==
        [OFOND.Bin(5, 45, [commodity2, commodity1, commodity1, commodity1])]
    @test sol.bins[supp1Step4, xdockStep1] ==
        [OFOND.Bin(5, 45, [commodity2, commodity1, commodity1, commodity1])]
    @test sol.bins[xdockStep4, plantStep1] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol.bins[xdockStep1, plantStep2] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol.bins[supp2Step4, plantStep1] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
    filledArcs = findnz(sol.bins)[3]
    @test length(filledArcs) == 5
    @test lowerBound ≈ 20.2
end
