supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]

xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]

@testset "Lower bound path" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # classic path computation
    path, cost = OFOND.lower_bound_path(
        sol, TTGraph, TSGraph, bundle11, supp1FromDel2, plantFromDel0
    )
    @test path == [supp1FromDel2, xdockFromDel1, plantFromDel0]
    @test cost ≈ (1e-5 + 1.6 + 0 + 0.4 + 5) + (1e-5 + 1.6 + 0 + 0.2 + 5)
    # change bins to change cost 
    push!(sol.bins[xdockStep4, plantStep1], OFOND.Bin(50))
    path, cost = OFOND.lower_bound_path(
        sol, TTGraph, TSGraph, bundle11, supp1FromDel2, plantFromDel0; use_bins=true
    )
    @test path == [supp1FromDel2, xdockFromDel1, plantFromDel0]
    @test cost ≈ (1e-5 + 1.6 + 0 + 0.4 + 5) + (1e-5 + 0 + 0 + 0.2 + 5)
    # change current cost to change path 
    empty!(sol.bins[xdockStep4, plantStep1])
    # TSGraph.currentCost[xdockStep4, plantStep1] = 1.0
    path, cost = OFOND.lower_bound_path(
        sol, TTGraph, TSGraph, bundle11, supp1FromDel2, plantFromDel0; current_cost=true
    )
    @test path == [supp1FromDel2, plantFromDel0]
    @test cost ≈ (2e-5 + 0 + 0.4 + 10)
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

@testset "Lower bound insertion" begin
    sol2 = OFOND.Solution(TTGraph2, TSGraph2, bundles)
    supp3Idx = TTGraph2.hashToIdx[hash(3, supplier3.hash)]
    plantIdx = TTGraph2.hashToIdx[hash(0, plant.hash)]
    # get 3 paths 
    # one directly admissible (classic one)
    path1, cost1 = OFOND.lower_bound_insertion(
        sol2, TTGraph2, TSGraph2, bundle33, supp3Idx, plantIdx
    )
    supp3FromDel2 = TTGraph2.hashToIdx[hash(2, supplier3.hash)]
    xdockFromDel1 = TTGraph2.hashToIdx[hash(1, xdock.hash)]
    plantFromDel0 = TTGraph2.hashToIdx[hash(0, plant.hash)]
    @test path1 == [supp3FromDel2, xdockFromDel1, plantFromDel0]
    @test cost1 ≈ 33.346173846153846
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
    end
    # path2 should not be admissible
    path2, cost2 = OFOND.lower_bound_path(
        sol2, TTGraph2, TSGraph2, bundle33, supp3Idx, plantIdx; current_cost=true
    )
    supp3FromDel3 = TTGraph2.hashToIdx[hash(3, supplier3.hash)]
    xdockFromDel2 = TTGraph2.hashToIdx[hash(2, xdock.hash)]
    xdock2FromDel1 = TTGraph2.hashToIdx[hash(1, xdock2.hash)]
    @test path2 ==
        [supp3FromDel3, xdockFromDel2, xdock2FromDel1, xdockFromDel1, plantFromDel0]
    @test cost2 ≈ 50.500079615384614
    @test !OFOND.is_path_admissible(TTGraph2, path2)
    # path3 should and be equal to path1
    path3, cost3 = OFOND.lower_bound_insertion(
        sol2, TTGraph2, TSGraph2, bundle33, supp3Idx, plantIdx; current_cost=true
    )
    @test path3 == path1
    @test cost3 ≈ 33.346173846153846
    @test OFOND.is_path_admissible(TTGraph2, path1)
end

supp2fromDel2 = TTGraph.hashToIdx[hash(2, supplier2.hash)]
supp2fromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]

@testset "Heuristic" begin
    # run heuristic and test solution as for benchmark
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    instance2 = deepcopy(instance)
    instance2.bundles[1].orders[1].bpUnits[:delivery] = 1
    instance2.bundles[2].orders[1].bpUnits[:direct] = 1
    instance2.bundles[3].orders[1].bpUnits[:delivery] = 1
    instance2.bundles[3].orders[2].bpUnits[:delivery] = 1

    lowerBound = OFOND.lower_bound!(sol, instance2)
    @test lowerBound ≈ 66.79915502262443
    @test sol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2fromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    filteredBundleOnNode = filter(p -> length(p.second) > 0, sol.bundlesOnNode)
    @test filteredBundleOnNode ==
        Dict(xdockFromDel1 => [1, 2, 3], plantFromDel0 => [1, 2, 3])
    # bundle 1 bins
    xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
    supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
    @test sol.bins[supp1Step3, xdockStep4] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[xdockStep4, plantStep1] == [
        OFOND.Bin(0, 50, [commodity1, commodity1, commodity2, commodity2]),
        OFOND.Bin(25, 25, [commodity2, commodity1]),
    ]
    # bundle 2 bins
    supp2Step3 = TSGraph.hashToIdx[hash(3, supplier2.hash)]
    @test sol.bins[supp2Step3, xdockStep4] == [OFOND.Bin(21, 30, [commodity2, commodity2])]
    # bundle 3 bins
    supp3Step3 = TSGraph.hashToIdx[hash(3, supplier3.hash)]
    @test sol.bins[supp3Step3, xdockStep4] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    supp3Step4 = TSGraph.hashToIdx[hash(4, supplier3.hash)]
    xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]
    @test sol.bins[supp3Step4, xdockStep1] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]
    @test sol.bins[xdockStep1, plantStep2] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    filledArcs = count(x -> length(x) > 0, findnz(sol.bins)[3])
    @test filledArcs == 6
    @test OFOND.compute_cost(instance2, sol) ≈ 70.79909502262444
end

@testset "Parallel Lower bound" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    instance2 = deepcopy(instance)
    instance2.bundles[1].orders[1].bpUnits[:delivery] = 1
    instance2.bundles[2].orders[1].bpUnits[:direct] = 1
    instance2.bundles[3].orders[1].bpUnits[:delivery] = 1
    instance2.bundles[3].orders[2].bpUnits[:delivery] = 1

    lowerBound = OFOND.parallel_lower_bound!(sol, instance2)
    @test lowerBound ≈ 66.79915502262443
    @test sol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2fromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    filteredBundleOnNode = filter(p -> length(p.second) > 0, sol.bundlesOnNode)
    @test filteredBundleOnNode ==
        Dict(xdockFromDel1 => [1, 2, 3], plantFromDel0 => [1, 2, 3])
    # bundle 1 bins
    xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
    supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
    @test sol.bins[supp1Step3, xdockStep4] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[xdockStep4, plantStep1] == [
        OFOND.Bin(0, 50, [commodity1, commodity1, commodity2, commodity2]),
        OFOND.Bin(25, 25, [commodity2, commodity1]),
    ]
    # bundle 2 bins
    supp2Step3 = TSGraph.hashToIdx[hash(3, supplier2.hash)]
    @test sol.bins[supp2Step3, xdockStep4] == [OFOND.Bin(21, 30, [commodity2, commodity2])]
    # bundle 3 bins
    supp3Step3 = TSGraph.hashToIdx[hash(3, supplier3.hash)]
    @test sol.bins[supp3Step3, xdockStep4] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    supp3Step4 = TSGraph.hashToIdx[hash(4, supplier3.hash)]
    xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]
    @test sol.bins[supp3Step4, xdockStep1] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]
    @test sol.bins[xdockStep1, plantStep2] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    filledArcs = count(x -> length(x) > 0, findnz(sol.bins)[3])
    @test filledArcs == 6
    @test OFOND.compute_cost(instance2, sol) ≈ 70.79909502262444
end

@testset "Lower bound filtering path" begin
    # usual filtering path
    path = OFOND.lower_bound_filtering_path(
        TTGraph, TSGraph, bundle11, supp1FromDel2, plantFromDel0
    )
    @test path == [supp1FromDel2, xdockFromDel1, plantFromDel0]
    # forcing direct path 
    bundle11.orders[1].bpUnits[:direct] = 0
    path = OFOND.lower_bound_filtering_path(
        TTGraph, TSGraph, bundle11, supp1FromDel2, plantFromDel0
    )
    @test path == [supp1FromDel2, plantFromDel0]
    # reverting change
    bundle11.orders[1].bpUnits[:direct] = 2
end

supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
supp2FromDel2 = TTGraph.hashToIdx[hash(2, supplier2.hash)]

@testset "Filtering computaion" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.lower_bound_filtering!(sol, instance)
    @test sol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    @test OFOND.is_feasible(instance, sol)
    @test OFOND.compute_cost(instance, sol) ≈ 67.838592760181

    # forcing direct path 
    bundle11.orders[1].bpUnits[:direct] = 0

    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.lower_bound_filtering!(sol, instance)
    @test sol.bundlePaths == [
        [supp1FromDel2, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    @test OFOND.is_feasible(instance, sol)
    # Cost went up because we faked the cost decrease at path computation time but not at solution updating time
    @test OFOND.compute_cost(instance, sol) ≈ 89.9497737556561
end

@testset "Parallel Filtering computation" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.parallel_lower_bound_filtering!(sol, instance)
    # Should give the exact same result as above
    @test sol.bundlePaths == [
        [supp1FromDel2, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    @test OFOND.is_feasible(instance, sol)
    @test OFOND.compute_cost(instance, sol) ≈ 89.9497737556561

    # reverting change
    bundle11.orders[1].bpUnits[:direct] = 2

    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.parallel_lower_bound_filtering!(sol, instance)
    @test sol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    @test OFOND.is_feasible(instance, sol)
    @test OFOND.compute_cost(instance, sol) ≈ 70.79909502262444
end