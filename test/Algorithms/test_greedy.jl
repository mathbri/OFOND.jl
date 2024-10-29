supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]

supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]

@testset "Greedy path" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # classic path computation
    path, cost = OFOND.greedy_path(
        sol, TTGraph, TSGraph, bundle11, supp1FromDel3, plantFromDel0, CAPACITIES
    )
    @test path == [supp1FromDel2, xdockFromDel1, plantFromDel0]
    # base*2 + delivery units*4 + outsource units*4 + stock*2 + platform cost + carbon cost
    @test cost ≈ 2e-5 + 2 * 4 + (20 / 50) * 4 + 2 * 5 + 20 / 100 + 20 / 50
    # changing global bin state to change path
    push!(sol.bins[supp1Step3, plantStep1], OFOND.Bin(50))
    path, cost = OFOND.greedy_path(
        sol, TTGraph, TSGraph, bundle11, supp1FromDel3, plantFromDel0, CAPACITIES
    )
    @test path == [supp1FromDel2, plantFromDel0]
    @test cost ≈ 10.4 + 1e-5
    # change current cost to change path cost
    empty!(sol.bins[supp1Step3, plantStep1])
    path, cost = OFOND.greedy_path(
        sol,
        TTGraph,
        TSGraph,
        bundle1,
        supp1FromDel3,
        plantFromDel0,
        CAPACITIES;
        current_cost=true,
    )
    @test path == [supp1FromDel2, plantFromDel0]
    @test cost ≈ 1e-5
end

# Modifying instance a little for testing
# Adding a cycle in the network that won't be one in the time expansion
network2 = deepcopy(network)
xdock2 = OFOND.NetworkNode("007", :xdock, "FR", "EU", true, 1.0)
OFOND.add_node!(network2, xdock2)
OFOND.add_arc!(network2, xdock, xdock2, xdock_to_port)
xdock2_to_xdock = OFOND.NetworkArc(:cross_plat, 1.0, 0, true, 4.0, false, 0.0, 50)
OFOND.add_arc!(network2, xdock2, xdock, xdock2_to_xdock)
# Cretaing new instance
TTGraph2 = OFOND.TravelTimeGraph(network2, bundles)
TSGraph2 = OFOND.TimeSpaceGraph(network2, 4)
instance2 = OFOND.Instance(network2, TTGraph2, TSGraph2, bundles, 4, dates, partNumbers)

@testset "Greedy insertion" begin
    sol2 = OFOND.Solution(TTGraph2, TSGraph2, bundles)
    supp3Idx = TTGraph2.hashToIdx[hash(3, supplier3.hash)]
    plantIdx = TTGraph2.hashToIdx[hash(0, plant.hash)]
    # get 3 paths 
    # one directly admissible (classic one)
    path1, cost1 = OFOND.greedy_insertion(
        sol2, TTGraph2, TSGraph2, bundle33, supp3Idx, plantIdx, CAPACITIES
    )
    supp3FromDel2 = TTGraph2.hashToIdx[hash(2, supplier3.hash)]
    xdockFromDel1 = TTGraph2.hashToIdx[hash(1, xdock.hash)]
    plantFromDel0 = TTGraph2.hashToIdx[hash(0, plant.hash)]
    @test path1 == [supp3FromDel2, xdockFromDel1, plantFromDel0]
    # 2 base arc cost + 2*2*6 for stock + 2*2*4 for delivery (bpDict = 2) + 2*(25/52)*4 for outsource + (25/52)*1 for carbon + 25/100 for xdock
    @test cost1 ≈ 2e-5 + 24 + 16 + (25 / 52) * 8 + 2 * (25 / 50 + 25 / 100)
    @test OFOND.is_path_admissible(TTGraph2, path1)
    # one neither : change scale of others to force the path
    TSGraph2.currentCost .*= 1e7
    xdockStep3 = TSGraph2.hashToIdx[hash(3, xdock.hash)]
    xdockStep4 = TSGraph2.hashToIdx[hash(4, xdock.hash)]
    supp3step2 = TSGraph2.hashToIdx[hash(2, supplier3.hash)]
    xdock2Step4 = TSGraph2.hashToIdx[hash(4, xdock2.hash)]
    plantStep1 = TSGraph2.hashToIdx[hash(1, plant.hash)]
    I = [xdockStep3, supp3step2, xdock2Step4, xdockStep4]
    J = [xdock2Step4, xdockStep3, xdockStep4, plantStep1]
    for (i, j) in zip(I, J)
        TSGraph2.currentCost[i, j] *= 1e-7
        # push!(sol2.bins[i, j], OFOND.Bin(50))
    end
    xdockStep4 = TSGraph2.hashToIdx[hash(4, xdock.hash)]
    xdockStep1 = TSGraph2.hashToIdx[hash(1, xdock.hash)]
    supp3step3 = TSGraph2.hashToIdx[hash(3, supplier3.hash)]
    xdock2Step1 = TSGraph2.hashToIdx[hash(1, xdock2.hash)]
    plantStep2 = TSGraph2.hashToIdx[hash(2, plant.hash)]
    I = [xdockStep4, supp3step3, xdock2Step1, xdockStep1]
    J = [xdock2Step1, xdockStep4, xdockStep1, plantStep2]
    for (i, j) in zip(I, J)
        TSGraph2.currentCost[i, j] *= 1e-7
        # push!(sol2.bins[i, j], OFOND.Bin(50))
    end
    # path2 should not be admissible
    path2, cost2 = OFOND.greedy_path(
        sol2,
        TTGraph2,
        TSGraph2,
        bundle33,
        supp3Idx,
        plantIdx,
        CAPACITIES;
        current_cost=true,
    )
    supp3FromDel3 = TTGraph2.hashToIdx[hash(3, supplier3.hash)]
    xdockFromDel2 = TTGraph2.hashToIdx[hash(2, xdock.hash)]
    xdock2FromDel1 = TTGraph2.hashToIdx[hash(1, xdock2.hash)]
    @test path2 ==
        [supp3FromDel3, xdockFromDel2, xdock2FromDel1, xdockFromDel1, plantFromDel0]
    @test cost2 ≈ 50.50016961538461
    @test !OFOND.is_path_admissible(TTGraph2, path2)
    # path3 should and be equal to path1
    path3, cost3 = OFOND.greedy_insertion(
        sol2,
        TTGraph2,
        TSGraph2,
        bundle33,
        supp3Idx,
        plantIdx,
        CAPACITIES;
        current_cost=true,
    )
    @test path3 == path1
    @test cost3 ≈ 73.57698788461539
    @test OFOND.is_path_admissible(TTGraph2, path3)
end

supp2fromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]

xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]

@testset "Heuristic" begin
    # run heuristic and test solution as for benchmark
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    instance2 = deepcopy(instance)
    instance2.bundles[1].orders[1].bpUnits[:delivery] = 1
    instance2.bundles[2].orders[1].bpUnits[:direct] = 1
    instance2.bundles[3].orders[1].bpUnits[:delivery] = 1
    instance2.bundles[3].orders[2].bpUnits[:delivery] = 1
    cost = OFOND.greedy!(sol, instance2)
    supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]
    supp2fromDel2 = TTGraph.hashToIdx[hash(2, supplier2.hash)]
    @test sol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2fromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    filteredBundleOnNode = filter(p -> length(p.second) > 0, sol.bundlesOnNode)
    @test filteredBundleOnNode ==
        Dict(xdockFromDel1 => [2, 1, 3], plantFromDel0 => [2, 1, 3])
    # bundle 1 bins
    xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
    @test sol.bins[supp1Step3, xdockStep4] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[xdockStep4, plantStep1] == [
        OFOND.Bin(0, 50, [commodity2, commodity2, commodity1, commodity1]),
        OFOND.Bin(25, 25, [commodity2, commodity1]),
    ]
    # bundle 2 bins
    supp2Step3 = TSGraph.hashToIdx[hash(3, supplier2.hash)]
    @test sol.bins[supp2Step3, xdockStep4] == [OFOND.Bin(21, 30, [commodity2, commodity2])]
    # bundle 3 bins
    supp3Step3 = TSGraph.hashToIdx[hash(3, supplier3.hash)]
    @test sol.bins[supp3Step3, xdockStep4] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    supp3Step4 = TSGraph.hashToIdx[hash(4, supplier3.hash)]
    @test sol.bins[supp3Step4, xdockStep1] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]
    @test sol.bins[xdockStep1, plantStep2] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    filledArcs = count(x -> length(x) > 0, findnz(sol.bins)[3])
    @test filledArcs == 6
    @test cost ≈ 70.79909502262444
end