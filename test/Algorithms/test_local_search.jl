supp1Step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]
TSPath = [supp1Step2, xdockStep3, portStep4, plantStep1]

xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]

@testset "Bin packing improvement" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.add_order!(sol, TSGraph, TSPath, order1)
    # add commodities so that this neighborhood change things
    push!(sol.bins[supp1Step2, xdockStep3], OFOND.Bin(50))
    push!(sol.bins[xdockStep3, portStep4], OFOND.Bin(45, 5, [commodity3]))
    # test with skipLinear
    costImprov = OFOND.bin_packing_improvement!(sol, instance)
    @test costImprov ≈ -4.0
    @test sol.bins[supp1Step2, xdockStep3] ==
        [OFOND.Bin(30, 20, [commodity1, commodity1]), OFOND.Bin(50)]
    @test sol.bins[xdockStep3, portStep4] ==
        [OFOND.Bin(25, 25, [commodity1, commodity1, commodity3])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    # test without skipLinear
    costImprov = OFOND.bin_packing_improvement!(sol, instance; skipLinear=false)
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
    costImprov = OFOND.bin_packing_improvement!(sol, instance; skipLinear=false)
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

@testset "Bundle reintroduction" begin
    # take greedy solution 
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # lower bound and greedy give the same solution but for greedy we need to adapt properties
    OFOND.lower_bound!(sol, instance)
    greedySol = deepcopy(sol)
    # remove bundle 1 with cost removed = 0 so nothing happens
    costImprov = OFOND.bundle_reintroduction!(sol, instance, bundle1, CAPACITIES)
    @test sol.bundlePaths == greedySol.bundlePaths
    @test costImprov ≈ 0.0
    # bundle1 and 3 are equal for the operator so when filtering bundel on nodes, bundle3 is also deleted but just bundle 1 is added back
    # also because of deletion and reinsertion, the order is now different in the vector
    # @test sol.bundlesOnNode == greedySol.bundlesOnNode

    # at removal bundle1 removed the commodity1 of bundle3 and and insertion the order was changed
    OFOND.add!(sol.bins[3, 12][1], commodity1)
    sort!(greedySol.bins[3, 12][1].content; rev=true)
    OFOND.add!(sol.bins[12, 17][1], commodity1)
    sort!(greedySol.bins[12, 17][1].content; rev=true)
    @test sol.bins == greedySol.bins
    # check with save_and_remove_bundle function
    otherSol = deepcopy(greedySol)
    oldBins, costRemoved = OFOND.save_and_remove_bundle!(
        otherSol, instance, [bundle1], [sol.bundlePaths[1]]
    )
    @test costRemoved <= 1e-5

    # correcting bundle2 bpDict
    instance.bundles[2].orders[1].bpUnits[:direct] = 1
    # remove bundle 2, has the same path so added = removed
    costImprov = OFOND.bundle_reintroduction!(sol, instance, bundle2, CAPACITIES)
    @test sol.bundlePaths == greedySol.bundlePaths
    @test costImprov ≈ 0.0
    # same thing as test above
    # @test sol.bundlesOnNode == greedySol.bundlesOnNode
    @test sol.bins == greedySol.bins
    #  check with save_and_remove_bundle and greedy_insertion
    otherSol = deepcopy(greedySol)
    oldBins, costRemoved = OFOND.save_and_remove_bundle!(
        otherSol, instance, [bundle2], [sol.bundlePaths[2]]
    )
    @test costRemoved ≈ -24.006
    supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
    newPath, pathCost = OFOND.greedy_insertion(
        otherSol, TTGraph, TSGraph, bundle2, supp2FromDel1, plantFromDel0, CAPACITIES
    )
    @test newPath == sol.bundlePaths[2]
    @test abs(pathCost + costRemoved) < 1e-3

    # problem with bundle1 = bundle3 also affects removal of commodities as its removes commodities from b1 and b3 than recompute the new path

    # change path bundle 3 
    OFOND.update_solution!(sol, instance, [bundle3]; remove=true)
    # as said above, need to reintroduce bundle1
    # TTPath = [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]
    OFOND.update_solution!(sol, instance, [bundle1, bundle3], [[3, 8, 15], TTPath])
    # adding commodities si that the filling is different after reinsertion
    OFOND.add!(sol.bins[xdockStep4, plantStep1][1], commodity3)
    OFOND.add!(sol.bins[supp1Step3, xdockStep4][1], commodity3)
    @test sol.bins[supp1Step3, xdockStep4] ==
        [OFOND.Bin(0, 50, [commodity1, commodity1, commodity2, commodity1, commodity3])]
    @test sol.bins[xdockStep4, plantStep1] ==
        [OFOND.Bin(25, 25, [commodity1, commodity1, commodity3])]
    # reinsert, has the same previous path
    instance.bundles[3].orders[1].bpUnits[:delivery] = 1
    instance.bundles[3].orders[2].bpUnits[:delivery] = 1
    costImprov = OFOND.bundle_reintroduction!(sol, instance, bundle3, CAPACITIES)
    # and the filling is different on those shared with bundle 1 
    @test sol.bundlePaths == greedySol.bundlePaths
    @test isapprox(costImprov, -24.0; atol=1e-3)
    # bundle1 commodities are removed when bundle3 commodities are on this arc because used in previous bundle3 path
    @test sol.bins[supp1Step3, xdockStep4] ==
        [OFOND.Bin(20, 30, [commodity3, commodity2, commodity1])]
    @test sol.bins[xdockStep4, plantStep1] ==
        [OFOND.Bin(0, 50, [commodity1, commodity1, commodity3, commodity2, commodity1])]
end

# for this and local search, one solution is to add another cross-dock to avoid putting bundle1 and 3 on a forbidden path

# Modifying instance a little for testing
# Adding a cycle in the network that won't be one in the time expansion
network2 = deepcopy(network)

xdock2 = OFOND.NetworkNode("006", :xdock, "FR", "EU", true, 1.0)
xdock3 = OFOND.NetworkNode("007", :xdock, "CN", "AS", true, 1.0)
supplier3 = OFOND.NetworkNode("008", :supplier, "CN", "AS", false, 0.0)
OFOND.add_node!(network2, xdock2)
OFOND.add_node!(network2, xdock3)
OFOND.add_node!(network2, supplier3)

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
OFOND.add_arc!(network2, supplier3, xdock, supp_to_plat)

# Modifying bundle 3 to make it not equal anymore to bundle 1
bundle11 = OFOND.Bundle(supplier1, plant, [order1], 1, bunH1, 10, 3)
bunH3 = hash(supplier3, hash(plant))
order33 = OFOND.Order(
    bunH3, 1, [commodity2, commodity1], hash(1, bunH3), 25, bpDict, 10, 6.0
)
order44 = OFOND.Order(
    bunH3, 2, [commodity1, commodity2], hash(1, bunH3), 25, bpDict, 10, 6.0
)
bundle33 = OFOND.Bundle(supplier3, plant, [order33, order44], 3, bunH3, 15, 3)

# Cretaing new instance
bundles[[1, 3]] = [bundle11, bundle33]
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
    OFOND.update_solution!(sol, instance2, [bundle2], [[supp2fromDel1, plantFromDel0]])

    bundles[1].orders[1].bpUnits[:cross_plat] = 1
    # testing just the bundle1 alone from xdock2 to plant 
    costImprov = OFOND.two_node_incremental!(
        sol, instance2, xdock2fromDel1, plantFromDel0, Int[]
    )
    # initial path is TTPath12
    # new path goes to xdock3 before plant
    @test costImprov ≈ -3.496
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
    costImprov = OFOND.two_node_incremental!(
        sol, instance2, xdock1FromDel2, plantFromDel0, Int[]
    )
    @test costImprov ≈ -7.504
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

    # TODO : test a case where lower bound insertion is better
    # then adding near full bins so that lowerBound and greedy don't propose the same
    # how to obtain a better lower bound insertion ?
end

# Some commodities get lost along the way if bundle 1 and bundle 3 have the same
commodity3 = OFOND.Commodity(2, hash("C789"), 14, 3.5)
commodity4 = OFOND.Commodity(2, hash("C789"), 11, 2.5)
instance2.bundles[3].orders[1].content[1] = commodity3
instance2.bundles[3].orders[1].content[2] = commodity4
instance2.bundles[3].orders[2].content[1] = commodity3
instance2.bundles[3].orders[2].content[2] = commodity4

@testset "Local search (full)" begin
    # mix of the above, from bad solution to good
    sol = OFOND.Solution(TTGraph2, TSGraph2, bundles)
    greedySol = deepcopy(sol)
    OFOND.lower_bound!(greedySol, instance2)
    # put bundle 1 on TTPath12 and bundle 3 on TTPath13
    OFOND.update_solution!(sol, instance2, [bundle11, bundle33], [TTPath112, TTPath313])
    OFOND.update_solution!(sol, instance2, [bundle2], [[supp2fromDel1, plantFromDel0]])
    # changing with full local search 
    OFOND.local_search!(sol, instance2; twoNode=true)
    @test sol.bundlePaths == greedySol.bundlePaths
    for (node, bundlesOnNode) in sol.bundlesOnNode
        sort!(bundlesOnNode)
        sort!(greedySol.bundlesOnNode[node])
    end
    @test sol.bundlesOnNode == greedySol.bundlesOnNode
    for arc in edges(TSGraph2.graph)
        for bin in sol.bins[arc.src, arc.dst]
            sort!(bin.content)
        end
        for bin in greedySol.bins[arc.src, arc.dst]
            sort!(bin.content)
        end
    end
    if sol.bins != greedySol.bins
        I, J, V = findnz(sol.bins)
        for (i, j) in zip(I, J)
            if sol.bins[i, j] != greedySol.bins[i, j]
                sort!(sol.bins[i, j])
                sort!(greedySol.bins[i, j])
            end
            if sol.bins[i, j] != greedySol.bins[i, j]
                println("Difference on arc $i-$j")
                println(sol.bins[i, j])
                println(greedySol.bins[i, j])
            end
        end
    end
    @test sol.bins == greedySol.bins
end