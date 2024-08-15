supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]

@testset "Greedy path" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # classic path computation
    bundle11 = deepcopy(bundle1)
    bundle11.orders[1].bpUnits[:direct] = 0
    path, cost = OFOND.greedy_path(
        sol, TTGraph, TSGraph, bundle11, supp1FromDel2, plantFromDel0
    )
    @test path == [supp1FromDel2, plantFromDel0]
    @test cost ≈ 10.004 + 1e-5
    # change opening factor to change path 
    path, cost = OFOND.greedy_path(
        sol, TTGraph, TSGraph, bundle1, supp1FromDel2, plantFromDel0
    )
    @test path == [supp1FromDel2, xdockFromDel1, plantFromDel0]
    @test cost ≈ 19.608 + 2e-5
    # change current cost to change path 
    # TSGraph.currentCost[xdockStep4, plantStep1] = 1.0
    path, cost = OFOND.greedy_path(
        sol, TTGraph, TSGraph, bundle1, supp1FromDel2, plantFromDel0; current_cost=true
    )
    @test path == [supp1FromDel2, plantFromDel0]
    @test cost ≈ 10.004 + 3e-5 + 1e-5
end

# Modifying instance a little for testing
# Adding a cycle in the network that won't be one in the time expansion
network2 = deepcopy(network)
supplier3 = OFOND.NetworkNode("003", :supplier, "CN", "AS", false, 0.0)
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
instance2 = OFOND.Instance(network2, TTGraph2, TSGraph2, [bundle4], 4, dates, partNumbers)

@testset "Greedy insertion" begin
    sol2 = OFOND.Solution(TTGraph2, TSGraph2, [bundle4])
    supp3Idx = TTGraph2.hashToIdx[hash(3, supplier3.hash)]
    plantIdx = TTGraph2.hashToIdx[hash(0, plant.hash)]
    # get 3 paths 
    # one directly admissible (classic one)
    path1, cost1 = OFOND.greedy_insertion(
        sol2, TTGraph2, TSGraph2, bundle4, supp3Idx, plantIdx
    )
    supp3FromDel2 = TTGraph2.hashToIdx[hash(2, supplier3.hash)]
    xdockFromDel1 = TTGraph2.hashToIdx[hash(1, xdock.hash)]
    plantFromDel0 = TTGraph2.hashToIdx[hash(0, plant.hash)]
    @test path1 == [supp3FromDel2, xdockFromDel1, plantFromDel0]
    # 3 base arc cost + 12 for lead + 0.5/50 for carbon and xdock + 2*4 + 0.5*4 for units
    @test cost1 ≈ 2e-5 + 12 + 0.01 + 10
    @test OFOND.is_path_admissible(TTGraph2, path1)
    # one neither : change scale of others to force the path
    TSGraph2.currentCost .*= 1e7
    xdockStep3 = TSGraph2.hashToIdx[hash(3, xdock.hash)]
    xdockStep4 = TSGraph2.hashToIdx[hash(4, xdock.hash)]
    supp3step2 = TSGraph2.hashToIdx[hash(2, supplier3.hash)]
    portStep4 = TSGraph2.hashToIdx[hash(4, port_l.hash)]
    plantStep1 = TSGraph2.hashToIdx[hash(1, plant.hash)]
    I = [xdockStep3, supp3step2, portStep4, xdockStep4]
    J = [portStep4, xdockStep3, xdockStep4, plantStep1]
    for (i, j) in zip(I, J)
        TSGraph2.currentCost[i, j] *= 1e-7
    end
    # path2 should not be admissible
    path2, cost2 = OFOND.greedy_path(
        sol2, TTGraph2, TSGraph2, bundle4, supp3Idx, plantIdx; current_cost=true
    )
    supp3FromDel3 = TTGraph2.hashToIdx[hash(3, supplier3.hash)]
    xdockFromDel2 = TTGraph2.hashToIdx[hash(2, xdock.hash)]
    portFromDel1 = TTGraph2.hashToIdx[hash(1, port_l.hash)]
    @test path2 ==
        [supp3FromDel3, xdockFromDel2, portFromDel1, xdockFromDel1, plantFromDel0]
    @test cost2 ≈ 6.005015 + 6.00003 + 6.00503 + 6.00503
    @test !OFOND.is_path_admissible(TTGraph2, path2)
    # path3 should and be equal to path1
    path3, cost3 = OFOND.greedy_insertion(
        sol2, TTGraph2, TSGraph2, bundle4, supp3Idx, plantIdx; current_cost=true
    )
    @test path3 == path1
    @test cost3 ≈ 56.00501 + 6.00503
    @test OFOND.is_path_admissible(TTGraph2, path3)
end

supp2fromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]

@testset "Heuristic" begin
    # run heuristic and test solution as for benchmark
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # As they were created, bpUnits dict and max del time doesn't match true properties
    instance2 = deepcopy(instance)
    instance2.bundles[1].orders[1].bpUnits[:delivery] = 1
    instance2.bundles[2].orders[1].bpUnits[:direct] = 1
    instance2.bundles[3].orders[1].bpUnits[:delivery] = 1
    instance2.bundles[3].orders[2].bpUnits[:delivery] = 1

    cost = OFOND.greedy!(sol, instance2)
    @test sol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2fromDel1, plantFromDel0],
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
    ]
    filteredBundleOnNode = filter(p -> length(p.second) > 0, sol.bundlesOnNode)
    @test filteredBundleOnNode == Dict(
        xdockFromDel1 => [bundle1, bundle3], plantFromDel0 => [bundle2, bundle1, bundle3]
    )
    @test sol.bins[supp1Step3, xdockStep4] ==
        [OFOND.Bin(5, 45, [commodity1, commodity1, commodity2, commodity1])]
    xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]
    @test sol.bins[xdockStep4, plantStep1] ==
        [OFOND.Bin(5, 45, [commodity1, commodity1, commodity2, commodity1])]
    @test sol.bins[supp1Step4, xdockStep1] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol.bins[xdockStep1, plantStep2] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol.bins[supp2Step4, plantStep1] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
    filledArcs = filter(x -> length(x) > 0, findnz(sol.bins)[3])
    @test length(filledArcs) == 5
    @test cost ≈ 71.634
end