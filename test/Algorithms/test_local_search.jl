supp1Step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]
TSPath = [supp1Step2, xdockStep3, portStep4, plantStep1]

xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]

commodity3 = OFOND.Commodity(2, hash("C789"), 5, 0.5)

@testset "Bin packing improvement" begin
    ALL_COMMODITIES = [commodity1]
    CAPACITIES = [10]
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.add_order!(sol, TSGraph, TSPath, order1)
    # add commodities so that this neighborhood change things
    push!(sol.bins[supp1Step2, xdockStep3], OFOND.Bin(50))
    push!(sol.bins[xdockStep3, portStep4], OFOND.Bin(45, 5, [commodity3]))
    # test with skipLinear
    costImprov = OFOND.bin_packing_improvement!(sol, instance, ALL_COMMODITIES, CAPACITIES)
    @test costImprov ≈ -4.0
    @test sol.bins[supp1Step2, xdockStep3] ==
        [OFOND.Bin(30, 20, [commodity1, commodity1]), OFOND.Bin(50)]
    @test sol.bins[xdockStep3, portStep4] ==
        [OFOND.Bin(25, 25, [commodity1, commodity1, commodity3])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    # test without skipLinear
    costImprov = OFOND.bin_packing_improvement!(
        sol, instance, ALL_COMMODITIES, CAPACITIES; skipLinear=false
    )
    @test costImprov ≈ 0.0
    @test sol.bins[supp1Step2, xdockStep3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[xdockStep3, portStep4] ==
        [OFOND.Bin(25, 25, [commodity1, commodity1, commodity3])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    # add arc so that length newBins is equal but inside different 
    push!(
        sol.bins[xdockStep4, plantStep1],
        OFOND.Bin(20, 30, [commodity3, commodity1, commodity2]),
    )
    # check it didn't change
    costImprov = OFOND.bin_packing_improvement!(
        sol, instance, ALL_COMMODITIES, CAPACITIES; skipLinear=false
    )
    @test costImprov ≈ 0.0
    @test sol.bins[xdockStep4, plantStep1] ==
        [OFOND.Bin(20, 30, [commodity3, commodity1, commodity2])]
end

@testset "Parallel bin packing improvement" begin
    println("\nParallel bin packing improvement")
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.add_order!(sol, TSGraph, TSPath, order1)
    # add commodities so that this neighborhood change things
    push!(sol.bins[supp1Step2, xdockStep3], OFOND.Bin(50))
    push!(sol.bins[xdockStep3, portStep4], OFOND.Bin(45, 5, [commodity3]))
    # test with skipLinear
    costImprov = OFOND.parallel_bin_packing_improvement!(sol, instance)
    @test costImprov ≈ -4.0
    @test sol.bins[supp1Step2, xdockStep3] ==
        [OFOND.Bin(30, 20, [commodity1, commodity1]), OFOND.Bin(50)]
    @test sol.bins[xdockStep3, portStep4] ==
        [OFOND.Bin(25, 25, [commodity1, commodity1, commodity3])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    # test without skipLinear
    costImprov = OFOND.parallel_bin_packing_improvement!(sol, instance; skipLinear=false)
    @test costImprov ≈ 0.0
    @test sol.bins[supp1Step2, xdockStep3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[xdockStep3, portStep4] ==
        [OFOND.Bin(25, 25, [commodity1, commodity1, commodity3])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    # add arc so that length newBins is equal but inside different 
    push!(
        sol.bins[xdockStep4, plantStep1],
        OFOND.Bin(20, 30, [commodity3, commodity1, commodity2]),
    )
    # check it didn't change
    costImprov = OFOND.parallel_bin_packing_improvement!(sol, instance; skipLinear=false)
    @test costImprov ≈ 0.0
    @test sol.bins[xdockStep4, plantStep1] ==
        [OFOND.Bin(20, 30, [commodity3, commodity1, commodity2])]
end

supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
TTPath = [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]

supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
TSPath2 = [supp1Step3, xdockStep4, plantStep1]

supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
TTPath2 = [supp1FromDel2, xdockFromDel1, plantFromDel0]

@testset "Revert solution" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # put order 1 on TTPath as the previous bins
    I = [supp1Step2, xdockStep3, portStep4]
    J = [xdockStep3, portStep4, plantStep1]
    bins = [
        [OFOND.Bin(30, 20, [commodity1, commodity1])],
        [OFOND.Bin(30, 20, [commodity1, commodity1])],
        [OFOND.Bin(30, 20, [commodity1, commodity1])],
    ]
    oldBins = sparse(I, J, bins)
    # Check the correct retrieval of previous bins
    OFOND.revert_solution!(sol, instance, [bundle11], [TTPath], oldBins)
    @test sol.bundlePaths == [TTPath, [-1, -1], [-1, -1]]
    @test filter(x -> length(x[2]) > 0, sol.bundlesOnNode) ==
        Dict(xdockFromDel2 => [1], portFromDel1 => [1], plantFromDel0 => [1])
    @test sol.bins[supp1Step2, xdockStep3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[xdockStep3, portStep4] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test count(x -> length(x) > 0, sol.bins) == 3

    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # put order 2 on other path as new bins 
    I = [supp1Step3, xdockStep4]
    J = [xdockStep4, plantStep1]
    for (i, j) in zip(I, J)
        push!(sol.bins[i, j], OFOND.Bin(30, 20, [commodity1, commodity1]))
    end
    OFOND.add_path!(sol, bundle11, TTPath2)
    # Check the correct retrieval of previous bins
    OFOND.revert_solution!(sol, instance, [bundle11], [TTPath], oldBins, [TTPath2])
    @test sol.bundlePaths == [TTPath, [-1, -1], [-1, -1]]
    @test filter(x -> length(x[2]) > 0, sol.bundlesOnNode) ==
        Dict(xdockFromDel2 => [1], portFromDel1 => [1], plantFromDel0 => [1])
    @test sol.bins[supp1Step3, xdockStep4] == [OFOND.Bin(50)]
    @test sol.bins[supp1Step2, xdockStep3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[xdockStep3, portStep4] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test count(x -> length(x) > 0, sol.bins) == 4
end

supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
supp3Step3 = TSGraph.hashToIdx[hash(3, supplier3.hash)]
supp3Step2 = TSGraph.hashToIdx[hash(2, supplier3.hash)]

supp3FromDel3 = TTGraph.hashToIdx[hash(3, supplier3.hash)]

@testset "Bundle reintroduction" begin
    # take greedy solution 
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # lower bound and greedy give the same solution but for greedy we need to adapt properties
    OFOND.lower_bound!(sol, instance)
    greedySol = deepcopy(sol)
    # remove bundle 1 with cost removed < threshold so nothing happens
    costImprov = OFOND.bundle_reintroduction!(
        sol, instance, bundle11, CAPACITIES; costThreshold=12.5
    )
    @test sol.bundlePaths == greedySol.bundlePaths
    @test isapprox(costImprov, 0.0; atol=1e-3)
    @test sol.bundlesOnNode == greedySol.bundlesOnNode
    @test sol.bins == greedySol.bins

    # remove bundle 2, has the same path so added = removed
    costImprov = OFOND.bundle_reintroduction!(sol, instance, bundle22, CAPACITIES)
    @test sol.bundlePaths == greedySol.bundlePaths
    @test isapprox(costImprov, 0.0; atol=1e-3)
    # same thing as test above
    @test filter(x -> length(x[2]) > 0, sol.bundlesOnNode) ==
        Dict(13 => [1, 3, 2], 20 => [1, 3, 2])
    @test sol.bins == greedySol.bins

    # Constructing a solution where bundle 3 is on TTPath3
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.update_solution!(sol, instance, bundle11, greedySol.bundlePaths[1])
    OFOND.update_solution!(sol, instance, bundle22, greedySol.bundlePaths[2])
    TTPath3 = [supp3FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]
    OFOND.update_solution!(sol, instance, bundle33, TTPath3)
    # adding commodities si that the filling is different after reinsertion
    push!(sol.bins[xdockStep4, plantStep1], OFOND.Bin(45, 5, [commodity3]))
    OFOND.add!(sol.bins[supp3Step3, xdockStep4][1], commodity3)
    # testing previous state of bins
    @test sol.bins[supp3Step2, xdockStep3] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    @test sol.bins[supp3Step3, xdockStep4] ==
        [OFOND.Bin(22, 30, [commodity2, commodity1, commodity3])]
    @test sol.bins[xdockStep4, plantStep1] == [
        OFOND.Bin(0, 50, [commodity1, commodity1, commodity2, commodity2]),
        OFOND.Bin(45, 5, [commodity3]),
    ]
    # reinserting bundle 3, has the same previous path
    costImprov = OFOND.bundle_reintroduction!(sol, instance, bundle33, CAPACITIES)
    # and the filling is different on those shared with bundle 1 
    @test sol.bundlePaths == greedySol.bundlePaths
    @test isapprox(costImprov, -20.0; atol=1e-3)
    @test sol.bins[supp3Step3, xdockStep4] ==
        [OFOND.Bin(22, 30, [commodity3, commodity2, commodity1])]
    @test sol.bins[xdockStep4, plantStep1] == [
        OFOND.Bin(0, 50, [commodity1, commodity1, commodity2, commodity2]),
        OFOND.Bin(20, 30, [commodity3, commodity2, commodity1]),
    ]
end

supp2FromDel2 = TTGraph.hashToIdx[hash(2, supplier2.hash)]
supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]

@testset "Reintroduce bundles" begin
    # Take two solutions 
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.update_solution!(sol, instance, bundle11, [supp1FromDel2, plantFromDel0])
    OFOND.update_solution!(sol, instance, bundle22, [supp2FromDel1, plantFromDel0])
    OFOND.update_solution!(sol, instance, bundle33, [supp3FromDel2, plantFromDel0])
    testSol = deepcopy(sol)
    # reintroduce all bundles at once and one bundle at a time
    costImprov = OFOND.bundle_reintroduction!(sol, instance, bundle11, CAPACITIES)
    costImprov += OFOND.bundle_reintroduction!(sol, instance, bundle22, CAPACITIES)
    costImprov += OFOND.bundle_reintroduction!(sol, instance, bundle33, CAPACITIES)
    costImprovTest = OFOND.reintroduce_bundles!(testSol, instance, [1, 2, 3])
    # Check the solutions are the same (3031674)
    @test costImprov ≈ costImprovTest ≈ -11.15061873
    @test sol.bins == testSol.bins
    @test sol.bundlePaths == testSol.bundlePaths
    @test testSol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    @test sol.bundlesOnNode == testSol.bundlesOnNode
end

# for this and local search, one solution is to add another cross-dock to avoid putting bundle1 and 3 on a forbidden path

# Modifying instance a little for testing
# Adding a cycle in the network that won't be one in the time expansion
network2 = deepcopy(network)

xdock2 = OFOND.NetworkNode("006", :xdock, "FR", "EU", true, 1.0)
xdock3 = OFOND.NetworkNode("007", :xdock, "CN", "AS", true, 1.0)
OFOND.add_node!(network2, xdock2)
OFOND.add_node!(network2, xdock3)

xdock1_to_2 = OFOND.NetworkArc(:cross_plat, 0.1, 1, true, 5.0, false, 0.0, 50)
xdock1_to_3 = OFOND.NetworkArc(:cross_plat, 0.1, 1, true, 4.0, false, 0.0, 50)
xdock2_to_3 = OFOND.NetworkArc(:cross_plat, 0.1, 0, true, 2.0, false, 0.0, 50)
xdock2_to_plant = OFOND.NetworkArc(:cross_plat, 0.1, 1, true, 6.0, false, 1.0, 50)
xdock3_to_plant = OFOND.NetworkArc(:cross_plat, 0.1, 1, true, 3.0, false, 1.0, 50)

OFOND.add_arc!(network2, xdock, xdock2, xdock1_to_2)
OFOND.add_arc!(network2, xdock, xdock3, xdock1_to_3)
OFOND.add_arc!(network2, xdock2, xdock3, xdock2_to_3)
OFOND.add_arc!(network2, xdock2, plant, xdock2_to_plant)
OFOND.add_arc!(network2, xdock3, plant, xdock3_to_plant)

# Creating new instance
TTGraph2 = OFOND.TravelTimeGraph(network2, bundles)
TSGraph2 = OFOND.TimeSpaceGraph(network2, 4)
instance2 = OFOND.Instance(network2, TTGraph2, TSGraph2, bundles, 4, dates, partNumbers)

# New TTPath
supp1FromDel3 = TTGraph2.hashToIdx[hash(3, supplier1.hash)]
xdock1FromDel2 = TTGraph2.hashToIdx[hash(2, xdock.hash)]
xdock2fromDel1 = TTGraph2.hashToIdx[hash(1, xdock2.hash)]
xdock3fromDel1 = TTGraph2.hashToIdx[hash(1, xdock3.hash)]
plantFromDel0 = TTGraph2.hashToIdx[hash(0, plant.hash)]
TTPath112 = [supp1FromDel3, xdock1FromDel2, xdock2fromDel1, plantFromDel0]
TTPath113 = [supp1FromDel3, xdock1FromDel2, xdock3fromDel1, plantFromDel0]

supp3FromDel3 = TTGraph2.hashToIdx[hash(3, supplier3.hash)]
TTPath313 = [supp3FromDel3, xdock1FromDel2, xdock3fromDel1, plantFromDel0]

supp2fromDel1 = TTGraph2.hashToIdx[hash(1, supplier2.hash)]

# New TSPath
xdock1Step3 = TSGraph2.hashToIdx[hash(3, xdock.hash)]
xdock2Step4 = TSGraph2.hashToIdx[hash(4, xdock2.hash)]
plantStep1 = TSGraph2.hashToIdx[hash(1, plant.hash)]
xdock3Step4 = TSGraph2.hashToIdx[hash(4, xdock3.hash)]

plantStep2 = TSGraph2.hashToIdx[hash(2, plant.hash)]

@testset "Two node incremental" begin
    sol = OFOND.Solution(TTGraph2, TSGraph2, bundles)
    # put bundle 1 on TTPath12 and bundle 3 on TTPath13
    OFOND.update_solution!(sol, instance2, [bundle11, bundle33], [TTPath112, TTPath313])
    OFOND.update_solution!(sol, instance2, [bundle22], [[supp2fromDel1, plantFromDel0]])

    bundles[1].orders[1].bpUnits[:cross_plat] = 1
    # testing just the bundle1 alone from xdock2 to plant 
    costImprov, bunCount = OFOND.two_node_incremental!(
        sol, instance2, xdock2fromDel1, plantFromDel0, Int[]
    )
    # initial path is TTPath12
    # new path goes to xdock3 before plant
    @test costImprov ≈ -3.3
    @test bunCount == 1
    xdock1FromDel2 = TTGraph2.hashToIdx[hash(2, xdock.hash)]
    @test sol.bundlePaths == [
        [supp1FromDel3, xdock1FromDel2, xdock2fromDel1, xdock3fromDel1, plantFromDel0],
        [supp2fromDel1, plantFromDel0],
        TTPath313,
    ]

    # testing bundle on nodes
    @test sol.bundlesOnNode[plantFromDel0] == [1, 3, 2]
    @test sol.bundlesOnNode[xdock1FromDel2] == [1, 3]
    @test sol.bundlesOnNode[xdock2fromDel1] == [1]
    @test sol.bundlesOnNode[xdock3fromDel1] == [3, 1]
    # testing bins
    # just bundle 1
    @test sol.bins[xdock1Step3, xdock2Step4] ==
        [OFOND.Bin(30, 20, [commodity1, commodity1])]
    # just bundle 3
    @test sol.bins[xdock1Step3, xdock3Step4] ==
        [OFOND.Bin(25, 25, [commodity2, commodity1])]
    # just bundle 1
    @test sol.bins[xdock2Step4, xdock3Step4] ==
        [OFOND.Bin(30, 20, [commodity1, commodity1])]
    # bundle 1 and 3
    @test sol.bins[xdock3Step4, plantStep1] ==
        [OFOND.Bin(5, 45, [commodity2, commodity1, commodity1, commodity1])]
    # nobody
    @test sol.bins[xdock2Step4, plantStep1] == OFOND.Bin[]

    # now testing bundle 1 and 3 together
    xdock1FromDel2 = TTGraph2.hashToIdx[hash(2, xdock.hash)]
    costImprov, bunCount = OFOND.two_node_incremental!(
        sol, instance2, xdock1FromDel2, plantFromDel0, Int[]
    )
    @test costImprov ≈ -7.7
    @test bunCount == 2
    @test sol.bundlePaths == [TTPath113, [supp2fromDel1, plantFromDel0], TTPath313]
    # testing bundle on nodes
    @test sol.bundlesOnNode[plantFromDel0] == [1, 3, 2]
    @test sol.bundlesOnNode[xdock1FromDel2] == [1, 3]
    @test sol.bundlesOnNode[xdock2fromDel1] == Int[]
    @test sort(sol.bundlesOnNode[xdock3fromDel1]) == [1, 3]
    # testing bins
    @test sol.bins[xdock1Step3, xdock2Step4] == OFOND.Bin[]
    @test length(sol.bins[xdock1Step3, xdock3Step4]) == 1
    @test sol.bins[xdock1Step3, xdock3Step4][1].capacity == 5
    @test sol.bins[xdock1Step3, xdock3Step4][1].load == 45
    @test sort(sol.bins[xdock1Step3, xdock3Step4][1].content) ==
        [commodity1, commodity1, commodity1, commodity2]
    xdock1Step4 = TSGraph2.hashToIdx[hash(4, xdock.hash)]
    xdock3Step1 = TSGraph2.hashToIdx[hash(1, xdock3.hash)]
    @test sol.bins[xdock1Step4, xdock3Step1] ==
        [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol.bins[xdock2Step4, xdock3Step4] == OFOND.Bin[]
    @test length(sol.bins[xdock3Step4, plantStep1]) == 1
    @test sol.bins[xdock3Step4, plantStep1][1].capacity == 5
    @test sol.bins[xdock3Step4, plantStep1][1].load == 45
    @test sort(sol.bins[xdock3Step4, plantStep1][1].content) ==
        [commodity1, commodity1, commodity1, commodity2]
    @test sol.bins[xdock3Step1, plantStep2] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
end

@testset "Two node common" begin
    sol = OFOND.Solution(TTGraph2, TSGraph2, bundles)
    # put bundle 1 on TTPath12 and bundle 3 on TTPath13
    OFOND.update_solution!(sol, instance2, [bundle11, bundle33], [TTPath112, TTPath313])
    OFOND.update_solution!(sol, instance2, [bundle22], [[supp2fromDel1, plantFromDel0]])

    bundles[1].orders[1].bpUnits[:cross_plat] = 1
    # testing just the bundle1 alone from xdock2 to plant 
    costImprov, bunCount = OFOND.two_node_common!(
        sol, instance2, xdock2fromDel1, plantFromDel0, Int[]
    )
    # initial path is TTPath12
    # new path goes to xdock3 before plant
    @test costImprov ≈ -3.3
    @test bunCount == 1
    xdock1FromDel2 = TTGraph2.hashToIdx[hash(2, xdock.hash)]
    @test sol.bundlePaths == [
        [supp1FromDel3, xdock1FromDel2, xdock2fromDel1, xdock3fromDel1, plantFromDel0],
        [supp2fromDel1, plantFromDel0],
        TTPath313,
    ]

    # testing bundle on nodes
    @test sol.bundlesOnNode[plantFromDel0] == [1, 3, 2]
    @test sol.bundlesOnNode[xdock1FromDel2] == [1, 3]
    @test sol.bundlesOnNode[xdock2fromDel1] == [1]
    @test sol.bundlesOnNode[xdock3fromDel1] == [3, 1]
    # testing bins
    # just bundle 1
    @test sol.bins[xdock1Step3, xdock2Step4] ==
        [OFOND.Bin(30, 20, [commodity1, commodity1])]
    # just bundle 3
    @test sol.bins[xdock1Step3, xdock3Step4] ==
        [OFOND.Bin(25, 25, [commodity2, commodity1])]
    # just bundle 1
    @test sol.bins[xdock2Step4, xdock3Step4] ==
        [OFOND.Bin(30, 20, [commodity1, commodity1])]
    # bundle 1 and 3
    @test sol.bins[xdock3Step4, plantStep1] ==
        [OFOND.Bin(5, 45, [commodity2, commodity1, commodity1, commodity1])]
    # nobody
    @test sol.bins[xdock2Step4, plantStep1] == OFOND.Bin[]

    # now testing bundle 1 and 3 together
    xdock1FromDel2 = TTGraph2.hashToIdx[hash(2, xdock.hash)]
    costImprov, bunCount = OFOND.two_node_common!(
        sol, instance2, xdock1FromDel2, plantFromDel0, Int[]
    )
    @test costImprov ≈ -7.7
    @test bunCount == 2
    @test sol.bundlePaths == [TTPath113, [supp2fromDel1, plantFromDel0], TTPath313]
    # testing bundle on nodes
    @test sol.bundlesOnNode[plantFromDel0] == [1, 3, 2]
    @test sol.bundlesOnNode[xdock1FromDel2] == [1, 3]
    @test sol.bundlesOnNode[xdock2fromDel1] == Int[]
    @test sort(sol.bundlesOnNode[xdock3fromDel1]) == [1, 3]
    # testing bins
    @test sol.bins[xdock1Step3, xdock2Step4] == OFOND.Bin[]
    @test length(sol.bins[xdock1Step3, xdock3Step4]) == 1
    @test sol.bins[xdock1Step3, xdock3Step4][1].capacity == 5
    @test sol.bins[xdock1Step3, xdock3Step4][1].load == 45
    @test sort(sol.bins[xdock1Step3, xdock3Step4][1].content) ==
        [commodity1, commodity1, commodity1, commodity2]
    xdock1Step4 = TSGraph2.hashToIdx[hash(4, xdock.hash)]
    xdock3Step1 = TSGraph2.hashToIdx[hash(1, xdock3.hash)]
    @test sol.bins[xdock1Step4, xdock3Step1] ==
        [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol.bins[xdock2Step4, xdock3Step4] == OFOND.Bin[]
    @test length(sol.bins[xdock3Step4, plantStep1]) == 1
    @test sol.bins[xdock3Step4, plantStep1][1].capacity == 5
    @test sol.bins[xdock3Step4, plantStep1][1].load == 45
    @test sort(sol.bins[xdock3Step4, plantStep1][1].content) ==
        [commodity1, commodity1, commodity1, commodity2]
    @test sol.bins[xdock3Step1, plantStep2] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
end

# Redefining commodities, instance and bundles to avoid errors
bunH1 = hash(supplier1, hash(plant))
bunH2 = hash(supplier2, hash(plant))
bunH3 = hash(supplier3, hash(plant))

commodity1 = OFOND.Commodity(hash(1, bunH1), hash("A123"), 10, 2.5)
commodity2 = OFOND.Commodity(hash(1, bunH2), hash("B456"), 15, 3.5)
commodity3 = OFOND.Commodity(hash(1, bunH3), hash("A123"), 10, 2.5)
commodity4 = OFOND.Commodity(hash(1, bunH3), hash("B456"), 15, 3.5)
commodity5 = OFOND.Commodity(hash(2, bunH3), hash("A123"), 10, 2.5)
commodity6 = OFOND.Commodity(hash(2, bunH3), hash("B456"), 15, 3.5)

order1 = OFOND.Order(bunH1, 1, [commodity1, commodity1])
order2 = OFOND.Order(bunH2, 1, [commodity2, commodity2])
order3 = OFOND.Order(bunH3, 1, [commodity3, commodity4])
order4 = OFOND.Order(bunH3, 2, [commodity5, commodity6])

bundle11 = OFOND.Bundle(supplier1, plant, [order1], 1, bunH1, 10, 2)
bundle22 = OFOND.Bundle(supplier2, plant, [order2], 2, bunH2, 15, 1)
bundle33 = OFOND.Bundle(supplier3, plant, [order3, order4], 3, bunH3, 10, 3)

bundles = [bundle11, bundle22, bundle33]
instance2.bundles[1:3] = bundles

instance2 = OFOND.add_properties(instance2, OFOND.tentative_first_fit, CAPACITIES)

@testset "Two node common incremental" begin
    sol = OFOND.Solution(TTGraph2, TSGraph2, bundles)
    # put bundle 1 on TTPath12 and bundle 3 on TTPath13
    OFOND.update_solution!(sol, instance2, [bundle11, bundle33], [TTPath112, TTPath313])
    OFOND.update_solution!(sol, instance2, [bundle22], [[supp2fromDel1, plantFromDel0]])

    bundles[1].orders[1].bpUnits[:cross_plat] = 1
    # testing just the bundle1 alone from xdock2 to plant 
    costImprov, bunCount = OFOND.two_node_common_incremental!(
        sol, instance2, xdock2fromDel1, plantFromDel0, Int[]
    )
    # initial path is TTPath12
    # new path is TTPath113 thanks to full reintroduction
    @test isapprox(-costImprov, 11.0; atol=1e-3)
    @test bunCount == 2
    xdock1FromDel2 = TTGraph2.hashToIdx[hash(2, xdock.hash)]
    @test sol.bundlePaths == [TTPath113, [supp2fromDel1, plantFromDel0], TTPath313]
    # testing bundle on nodes
    @test sort(sol.bundlesOnNode[plantFromDel0]) == [1, 2, 3]
    @test sort(sol.bundlesOnNode[xdock1FromDel2]) == [1, 3]
    @test sol.bundlesOnNode[xdock2fromDel1] == Int[]
    @test sort(sol.bundlesOnNode[xdock3fromDel1]) == [1, 3]
    # testing bins
    # path to plant step 1 (order 1 and order 3)
    @test sol.bins[supp1Step2, xdock1Step3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[supp3Step2, xdock1Step3] == [OFOND.Bin(27, 25, [commodity4, commodity3])]
    @test sol.bins[xdock1Step3, xdock3Step4] ==
        [OFOND.Bin(5, 45, [commodity4, commodity3, commodity1, commodity1])]
    @test sol.bins[xdock3Step4, plantStep1] ==
        [OFOND.Bin(5, 45, [commodity4, commodity3, commodity1, commodity1])]
    supp2Step4 = TSGraph2.hashToIdx[hash(4, supplier2.hash)]
    @test sol.bins[supp2Step4, plantStep1] == [OFOND.Bin(21, 30, [commodity2, commodity2])]
    # path to plant step 2
    xdock1Step4 = TSGraph2.hashToIdx[hash(4, xdock.hash)]
    @test sol.bins[supp1Step3, xdock1Step4] == OFOND.Bin[]
    @test sol.bins[supp3Step3, xdock1Step4] == [OFOND.Bin(27, 25, [commodity6, commodity5])]
    xdock3Step1 = TSGraph2.hashToIdx[hash(1, xdock3.hash)]
    @test sol.bins[xdock1Step4, xdock3Step1] ==
        [OFOND.Bin(25, 25, [commodity6, commodity5])]
    @test sol.bins[xdock3Step1, plantStep2] == [OFOND.Bin(25, 25, [commodity6, commodity5])]
    supp2Step1 = TSGraph2.hashToIdx[hash(1, supplier2.hash)]
    @test sol.bins[supp2Step1, plantStep2] == OFOND.Bin[]

    # now testing bundle 1 and 3 together
    costImprov, bunCount = OFOND.two_node_common_incremental!(
        sol, instance2, xdock1FromDel2, plantFromDel0, Int[]
    )
    @test isapprox(costImprov, 0.0; atol=1e-3)
    @test bunCount == 2
    @test sol.bundlePaths == [TTPath113, [supp2fromDel1, plantFromDel0], TTPath313]
    # testing bundle on nodes
    @test sort(sol.bundlesOnNode[plantFromDel0]) == [1, 2, 3]
    @test sort(sol.bundlesOnNode[xdock1FromDel2]) == [1, 3]
    @test sol.bundlesOnNode[xdock2fromDel1] == Int[]
    @test sort(sol.bundlesOnNode[xdock3fromDel1]) == [1, 3]
    # testing bins
    # path to plant step 1 (order 1 and order 3)
    @test sol.bins[supp1Step2, xdock1Step3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[supp3Step2, xdock1Step3] == [OFOND.Bin(27, 25, [commodity4, commodity3])]
    @test sol.bins[xdock1Step3, xdock3Step4] ==
        [OFOND.Bin(5, 45, [commodity3, commodity4, commodity1, commodity1])]
    @test sol.bins[xdock3Step4, plantStep1] ==
        [OFOND.Bin(5, 45, [commodity3, commodity4, commodity1, commodity1])]
    @test sol.bins[supp2Step4, plantStep1] == [OFOND.Bin(21, 30, [commodity2, commodity2])]
    # path to plant step 2
    @test sol.bins[supp1Step3, xdock1Step4] == OFOND.Bin[]
    @test sol.bins[supp3Step3, xdock1Step4] == [OFOND.Bin(27, 25, [commodity6, commodity5])]
    sort!(sol.bins[xdock1Step4, xdock3Step1][1].content)
    @test sol.bins[xdock1Step4, xdock3Step1] ==
        [OFOND.Bin(25, 25, [commodity5, commodity6])]
    sort!(sol.bins[xdock3Step1, plantStep2][1].content)
    @test sol.bins[xdock3Step1, plantStep2] == [OFOND.Bin(25, 25, [commodity5, commodity6])]
    @test sol.bins[supp2Step1, plantStep2] == OFOND.Bin[]
end

@testset "All two nodes" begin
    # Take two solutions
    sol = OFOND.Solution(TTGraph2, TSGraph2, bundles)
    OFOND.update_solution!(sol, instance2, [bundle11, bundle33], [TTPath112, TTPath313])
    OFOND.update_solution!(sol, instance2, [bundle22], [[supp2fromDel1, plantFromDel0]])
    testSol = deepcopy(sol)
    # reintroduce all two nodes and one at a time
    costImprov, bunCount = OFOND.two_node_common_incremental!(
        sol, instance2, xdock2fromDel1, plantFromDel0, Int[]
    )
    # The only one that actually triggers is xdock2-plant
    plantNodes = findall(x -> x.type == :plant, TTGraph2.networkNodes)
    dstNodes = vcat(TTGraph2.commonNodes, plantNodes)
    costImprovTest, bunCountTest = OFOND.all_two_nodes!(
        testSol, instance2, TTGraph2.commonNodes, dstNodes; isShuffled=true
    )
    @test costImprov ≈ costImprovTest ≈ -11.0 + 3e-5
    @test bunCount == bunCountTest == 2
    @test sol.bundlePaths == [TTPath113, [supp2fromDel1, plantFromDel0], TTPath313]
    @test sol.bundlePaths == testSol.bundlePaths
    I, J, V = findnz(sol.bins)
    for (i, j) in zip(I, J)
        for bin in sol.bins[i, j]
            sort!(bin.content; by=x -> hash(x))
        end
        for bin in testSol.bins[i, j]
            sort!(bin.content; by=x -> hash(x))
        end
    end
    @test sol.bins == testSol.bins
    bundlesOnNode = filter(x -> !isempty(x[2]), sol.bundlesOnNode)
    for (node, bundles) in bundlesOnNode
        sort!(bundles)
    end
    bundlesOnNodeTest = filter(x -> !isempty(x[2]), testSol.bundlesOnNode)
    for (node, bundles) in bundlesOnNodeTest
        sort!(bundles)
    end
    @test sol.bundlesOnNode == testSol.bundlesOnNode
end

@testset "Local search (full)" begin
    # mix of the above, from bad solution to good
    sol = OFOND.Solution(TTGraph2, TSGraph2, bundles)
    # put bundle 1 on TTPath12 and bundle 3 on TTPath13
    OFOND.update_solution!(sol, instance2, [bundle11, bundle33], [TTPath112, TTPath313])
    OFOND.update_solution!(sol, instance2, [bundle2], [[supp2fromDel1, plantFromDel0]])
    # changing with full local search 
    costImprov = OFOND.local_search!(sol, instance2)
    # new path is TTPath113 thanks to full reintroduction
    @test isapprox(-costImprov, 14.33524411764706; atol=1e-3)
    xdock1FromDel1 = TTGraph2.hashToIdx[hash(1, xdock.hash)]
    xdock1FromDel2 = TTGraph2.hashToIdx[hash(2, xdock.hash)]
    supp2fromDel2 = TTGraph2.hashToIdx[hash(2, supplier2.hash)]
    @test sol.bundlePaths ==
        [TTPath113, [supp2fromDel2, xdock1FromDel1, plantFromDel0], TTPath313]
    # testing bundle on nodes
    @test sort(sol.bundlesOnNode[plantFromDel0]) == [1, 2, 3]
    @test sort(sol.bundlesOnNode[xdock1FromDel2]) == [1, 3]
    @test sort(sol.bundlesOnNode[xdock3fromDel1]) == [1, 3]
    @test sort(sol.bundlesOnNode[xdock1FromDel1]) == [2]
    @test sum(x -> length(x[2]), sol.bundlesOnNode) == 8
    # testing bins
    # sorting bins for ease of testing content 
    for arc in edges(instance2.timeSpaceGraph.graph)
        for bin in sol.bins[arc.src, arc.dst]
            sort!(bin.content)
        end
    end
    # path to plant step 1 (order 1 and order 3)
    @test sol.bins[supp1Step2, xdock1Step3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[supp3Step2, xdock1Step3] == [OFOND.Bin(27, 25, [commodity3, commodity4])]
    # The order is sometimes mixed up 
    bins1 = [OFOND.Bin(5, 45, [commodity3, commodity1, commodity1, commodity4])]
    bins2 = [OFOND.Bin(5, 45, [commodity1, commodity1, commodity3, commodity4])]
    @test (sol.bins[xdock1Step3, xdock3Step4] == bins1) ||
        (sol.bins[xdock1Step3, xdock3Step4] == bins2)
    @test (sol.bins[xdock3Step4, plantStep1] == bins1) ||
        (sol.bins[xdock3Step4, plantStep1] == bins2)
    supp2Step3 = TSGraph2.hashToIdx[hash(3, supplier2.hash)]
    xdock1Step4 = TSGraph2.hashToIdx[hash(4, xdock.hash)]
    @test sol.bins[supp2Step3, xdock1Step4] == [OFOND.Bin(21, 30, [commodity2, commodity2])]
    @test sol.bins[xdock1Step4, plantStep1] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
    # path to plant step 2
    @test sol.bins[supp1Step3, xdock1Step4] == OFOND.Bin[]
    @test sol.bins[supp3Step3, xdock1Step4] == [OFOND.Bin(27, 25, [commodity5, commodity6])]
    xdock3Step1 = TSGraph2.hashToIdx[hash(1, xdock3.hash)]
    @test sol.bins[xdock1Step4, xdock3Step1] ==
        [OFOND.Bin(25, 25, [commodity5, commodity6])]
    @test sol.bins[xdock3Step1, plantStep2] == [OFOND.Bin(25, 25, [commodity5, commodity6])]
    @test sum(x -> length(x), sol.bins) == 9
end

@testset "Allow / forbid directs" begin
    bpDictForbid = Dict(
        :direct => 100,
        :cross_plat => 1,
        :delivery => 1,
        :oversea => 1,
        :port_transport => 1,
    )
    bpDictAllowed = Dict(
        :direct => 1, :cross_plat => 1, :delivery => 1, :oversea => 1, :port_transport => 1
    )
    # Check the correct modification of bundles 
    OFOND.forbid_directs!(instance2)
    @test instance2.bundles[1].orders[1].bpUnits == bpDictForbid
    @test instance2.bundles[2].orders[1].bpUnits == bpDictForbid
    @test instance2.bundles[3].orders[1].bpUnits == bpDictForbid
    @test instance2.bundles[3].orders[2].bpUnits == bpDictForbid
    OFOND.allow_directs!(instance2)
    @test instance2.bundles[1].orders[1].bpUnits == bpDictAllowed
    @test instance2.bundles[2].orders[1].bpUnits == bpDictAllowed
    @test instance2.bundles[3].orders[1].bpUnits == bpDictAllowed
    @test instance2.bundles[3].orders[2].bpUnits == bpDictAllowed

    # Take a solution with only directs 
    sol = OFOND.Solution(TTGraph2, TSGraph2, bundles)
    OFOND.update_solution!(sol, instance2, bundle1, [supp1FromDel2, plantFromDel0])
    OFOND.update_solution!(sol, instance2, bundle2, [supp2fromDel1, plantFromDel0])
    OFOND.update_solution!(sol, instance2, bundle3, [supp3FromDel2, plantFromDel0])
    OFOND.forbid_directs!(instance2)
    bundle11.orders[1].bpUnits[:delivery] = 10
    # Reintroduce bundle 1 and check it is not direct anymore (even with a cost increase)
    costImprov = OFOND.bundle_reintroduction!(
        sol, instance2, bundle11, CAPACITIES; directReIntro=true
    )
    @test costImprov ≈ -5 + 3e-5
    @test sol.bundlePaths == [
        [supp1FromDel3, xdock1FromDel2, xdock3fromDel1, plantFromDel0],
        [supp2fromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
end

@testset "Large local search" begin
    # mix of the above, from bad solution to good
    sol = OFOND.Solution(TTGraph2, TSGraph2, bundles)
    # put bundle 1 on TTPath12 and bundle 3 on TTPath13
    OFOND.update_solution!(
        sol,
        instance2,
        [bundle11, bundle33],
        [[supp1FromDel2, plantFromDel0], [supp3FromDel2, plantFromDel0]],
    )
    OFOND.update_solution!(sol, instance2, [bundle2], [[supp2fromDel1, plantFromDel0]])
    # changing with full local search 
    costImprov = OFOND.large_local_search!(sol, instance2)
    # new path is TTPath113 thanks to full reintroduction
    # TODO : sum of improvements is not the total improvement, why .
    @test isapprox(-costImprov, 26.05067873303166; atol=1e-3)
    xdock1FromDel1 = TTGraph2.hashToIdx[hash(1, xdock.hash)]
    xdock1FromDel2 = TTGraph2.hashToIdx[hash(2, xdock.hash)]
    supp2fromDel2 = TTGraph2.hashToIdx[hash(2, supplier2.hash)]
    @test sol.bundlePaths ==
        [TTPath113, [supp2fromDel2, xdock1FromDel1, plantFromDel0], TTPath313]
    # testing bundle on nodes
    @test sort(sol.bundlesOnNode[plantFromDel0]) == [1, 2, 3]
    @test sort(sol.bundlesOnNode[xdock1FromDel2]) == [1, 3]
    @test sort(sol.bundlesOnNode[xdock3fromDel1]) == [1, 3]
    @test sort(sol.bundlesOnNode[xdock1FromDel1]) == [2]
    @test sum(x -> length(x[2]), sol.bundlesOnNode) == 8
    # testing bins
    # sorting bins for ease of testing content 
    for arc in edges(instance2.timeSpaceGraph.graph)
        for bin in sol.bins[arc.src, arc.dst]
            sort!(bin.content)
        end
    end
    # path to plant step 1 (order 1 and order 3)
    @test sol.bins[supp1Step2, xdock1Step3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[supp3Step2, xdock1Step3] == [OFOND.Bin(27, 25, [commodity3, commodity4])]
    # The order is sometimes mixed up 
    bins1 = [OFOND.Bin(5, 45, [commodity3, commodity1, commodity1, commodity4])]
    bins2 = [OFOND.Bin(5, 45, [commodity1, commodity1, commodity3, commodity4])]
    @test (sol.bins[xdock1Step3, xdock3Step4] == bins1) ||
        (sol.bins[xdock1Step3, xdock3Step4] == bins2)
    @test (sol.bins[xdock3Step4, plantStep1] == bins1) ||
        (sol.bins[xdock3Step4, plantStep1] == bins2)
    supp2Step3 = TSGraph2.hashToIdx[hash(3, supplier2.hash)]
    xdock1Step4 = TSGraph2.hashToIdx[hash(4, xdock.hash)]
    @test sol.bins[supp2Step3, xdock1Step4] == [OFOND.Bin(21, 30, [commodity2, commodity2])]
    @test sol.bins[xdock1Step4, plantStep1] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
    # path to plant step 2
    @test sol.bins[supp1Step3, xdock1Step4] == OFOND.Bin[]
    @test sol.bins[supp3Step3, xdock1Step4] == [OFOND.Bin(27, 25, [commodity5, commodity6])]
    xdock3Step1 = TSGraph2.hashToIdx[hash(1, xdock3.hash)]
    @test sol.bins[xdock1Step4, xdock3Step1] ==
        [OFOND.Bin(25, 25, [commodity5, commodity6])]
    @test sol.bins[xdock3Step1, plantStep2] == [OFOND.Bin(25, 25, [commodity5, commodity6])]
    @test sum(x -> length(x), sol.bins) == 9
end