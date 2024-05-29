@testset "is path partial" begin
    @test !OFOND.is_path_partial(TTGraph, bundle1, TTPath)
    TTPath2 = TTPath[2:end]
    @test OFOND.is_path_partial(TTGraph, bundle1, TTPath2)
    TTPath3 = TTPath[1:(end - 1)]
    @test OFOND.is_path_partial(TTGraph, bundle1, TTPath3)
end

supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
supp1FromDel1 = TTGraph.hashToIdx[hash(1, supplier1.hash)]

xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]

portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
TTPath = [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]

@testset "remove shortcuts" begin
    path = [supp1FromDel3, supp1FromDel2, xdockFromDel1]
    OFOND.remove_shortcuts!(path, TTGraph)
    @test path == [supp1FromDel2, xdockFromDel1]
    path = [supp1FromDel3, supp1FromDel2, supp1FromDel1, plantFromDel0]
    OFOND.remove_shortcuts!(path, TTGraph)
    @test path == [supp1FromDel1, plantFromDel0]
    OFOND.remove_shortcuts!(TTPath, TTGraph)
    @test TTPath == [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]
end

sol = OFOND.Solution(TTGraph, TSGraph, bundles)

@testset "add bundle" begin
    # path of length 0
    costAdded = OFOND.add_bundle!(sol, instance, bundle1, Int[])
    @test costAdded ≈ 0.0
    @test sol.bundlePaths == [[-1, -1], [-1, -1], [-1, -1]]
    I, J, V = findnz(sol.bins)
    @test V == [OFOND.Bin[] for _ in I]
    # add shortcut to form a second path and verify that both have the same updates 
    path1 = [supp1FromDel3, supp1FromDel2, plantFromDel0]
    costAdded1 = OFOND.add_bundle!(sol, instance, bundle1, path1)
    sol2 = OFOND.Solution(TTGraph, TSGraph, bundles)
    path2 = [supp1FromDel2, plantFromDel0]
    costAdded2 = OFOND.add_bundle!(sol2, instance, bundle1, path2)
    @test costAdded1 ≈ costAdded2 ≈ 20.2
    @test sol.bundlePaths == sol2.bundlePaths
    @test sol.bundlesOnNode == sol2.bundlesOnNode
    @test sol.bins == sol2.bins
    # test with partial path and skipFill because no ther possibilities
    OFOND.add_bundle!(
        sol, instance, bundle1, [supp1FromDel2, xdockFromDel1, plantFromDel0]; skipFill=true
    )
    costAdded = OFOND.add_bundle!(
        sol,
        instance,
        bundle1,
        [supp1FromDel3, supp1FromDel2, 15, xdockFromDel1];
        skipFill=true,
    )
    @test costAdded ≈ 0.0
    @test sol.bundlePaths[1] == [supp1FromDel2, 15, xdockFromDel1, plantFromDel0]
end

supp1Step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]

supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
portStep1 = TSGraph.hashToIdx[hash(1, port_l.hash)]
plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]

@testset "get bins updated" begin
    # give one or two bundles TTPaths and verify the sparse matrix obtained
    binsUpdated = OFOND.get_bins_updated(
        TSGraph, TTGraph, [bundle1, bundle3], [TTPath, TTPath]
    )
    I, J, V = findnz(binsUpdated)
    @test I == [supp1Step2, supp1Step3, xdockStep4, xdockStep3, portStep4, portStep1]
    @test J == [xdockStep3, xdockStep4, portStep1, portStep4, plantStep1, plantStep2]
    @test V == fill(true, 6)
end

sol = OFOND.Solution(TTGraph, TSGraph, bundles)
OFOND.add_bundle!(sol, instance, bundle3, TTPath)
# modify bins for the refill bins to actually do something
I = [supp1Step2, xdockStep3, portStep4, supp1Step3, xdockStep4, portStep1]
J = [xdockStep3, portStep4, plantStep1, xdockStep4, portStep1, plantStep2]
for (i, j) in zip(I, J)
    push!(sol.bins[i, j], OFOND.Bin(15, 5, [commodity3]))
end

@testset "refill bins" begin
    # first is closely related to bin packing
    bins = [
        OFOND.Bin(10, 10, [commodity1]),
        OFOND.Bin(5, 15, [commodity1, commodity3]),
        OFOND.Bin(5, 15, [commodity2]),
    ]
    newBins = OFOND.refill_bins!(bins, 20)
    @test length(bins) == 2
    @test newBins == -1
    @test bins == [
        OFOND.Bin(0, 20, [commodity2, commodity3]),
        OFOND.Bin(0, 20, [commodity1, commodity1]),
    ]

    bins = fill(OFOND.Bin(20), 3)
    newBins = OFOND.refill_bins!(bins, 20)
    @test newBins == -3
    @test bins == OFOND.Bin[]

    # other is to check that that this refilling is done on every arcs stated in working arcs
    binsUpdated = OFOND.get_bins_updated(TSGraph, TTGraph, [bundle3], [TTPath])
    costAdded = OFOND.refill_bins!(sol, TSGraph, binsUpdated)
    # linear costs didn't but cost reduced by 4 * 4.0 = 16.0, 1 bin per consolidated arcs
    @test costAdded ≈ -16.0
    # linear arcs not refilled
    @test sol.bins[supp1Step2, xdockStep3] ==
        [OFOND.Bin(25, 25, [commodity2, commodity1]), OFOND.Bin(15, 5, [commodity3])]
    @test sol.bins[supp1Step3, xdockStep4] ==
        [OFOND.Bin(25, 25, [commodity2, commodity1]), OFOND.Bin(15, 5, [commodity3])]
    # consolidated arcs refilled 
    @test sol.bins[portStep4, plantStep1] ==
        [OFOND.Bin(20, 30, [commodity2, commodity1, commodity3])]
    @test sol.bins[portStep1, plantStep2] ==
        [OFOND.Bin(20, 30, [commodity2, commodity1, commodity3])]
    @test sol.bins[xdockStep3, portStep4] ==
        [OFOND.Bin(20, 30, [commodity2, commodity1, commodity3])]
    @test sol.bins[xdockStep4, portStep1] ==
        [OFOND.Bin(20, 30, [commodity2, commodity1, commodity3])]
end

sol = OFOND.Solution(TTGraph, TSGraph, bundles)
OFOND.add_bundle!(sol, instance, bundle3, TTPath)
I = [supp1Step2, xdockStep3, portStep4, supp1Step3, xdockStep4, portStep1]
J = [xdockStep3, portStep4, plantStep1, xdockStep4, portStep1, plantStep2]
for (i, j) in zip(I, J)
    push!(sol.bins[i, j], OFOND.Bin(15, 5, [commodity3]))
end

# TODO : remove the [1] and test the old part returned
@testset "remove bundle" begin
    # test with empty, partial and normal path
    # empty and full path should be the same
    sol2 = deepcopy(sol)
    costAdded2 = OFOND.remove_bundle!(sol2, instance, bundle3, Int[])[1]
    sol3 = deepcopy(sol)
    costAdded3 = OFOND.remove_bundle!(sol3, instance, bundle3, TTPath)[1]
    # test that commodities are not in the bins but the bins are still there
    emptySol = OFOND.Solution(TTGraph, TSGraph, bundles)
    @test costAdded2 ≈ costAdded3 ≈ -41.0
    @test sol2.bundlePaths == sol3.bundlePaths == emptySol.bundlePaths
    @test sol2.bundlesOnNode == sol3.bundlesOnNode == emptySol.bundlesOnNode
    @test sol2.bins == sol3.bins
    V2 = findnz(sol2.bins)[3]
    filteredV2 = filter(x -> length(x) > 0, V2)
    V3 = findnz(sol3.bins)[3]
    filteredV3 = filter(x -> length(x) > 0, V3)
    @test all(bins -> bins == [OFOND.Bin(50), OFOND.Bin(15, 5, [commodity3])], filteredV2)
    @test all(bins -> bins == [OFOND.Bin(50), OFOND.Bin(15, 5, [commodity3])], filteredV3)
    # tests with partial path
    sol4 = deepcopy(sol)
    costAdded4 = OFOND.remove_bundle!(
        sol4, instance, bundle3, [supp1FromDel3, xdockFromDel2, portFromDel1]
    )[1]
    @test costAdded4 ≈ -28.5
    @test sol4.bundlePaths ==
        [[-1, -1], [-1, -1], [supp1FromDel3, portFromDel1, plantFromDel0]]
    @test sol4.bundlesOnNode[xdockFromDel2] == OFOND.Bundle[]
    @test sol4.bundlesOnNode[portFromDel1] == [bundle3]
    @test sol4.bins[xdockStep3, portStep4] ==
        [OFOND.Bin(50), OFOND.Bin(15, 5, [commodity3])]
    @test sol4.bins[portStep4, plantStep1] ==
        [OFOND.Bin(25, 25, [commodity2, commodity1]), OFOND.Bin(15, 5, [commodity3])]
end

sol = OFOND.Solution(TTGraph, TSGraph, bundles)
emptySol = OFOND.Solution(TTGraph, TSGraph, bundles)

@testset "update solution" begin
    # mix of all the above
    costAdded = OFOND.update_solution!(sol, instance, [bundle1, bundle3], [TTPath, TTPath])
    println("Paths before removal : $(sol.bundlePaths)")
    # println(sol.bundlesOnNode)
    # println(sol.bins)
    @test sol.bundlePaths == [TTPath, [-1, -1], TTPath]
    costRemoved = OFOND.update_solution!(sol, instance, [bundle1, bundle3]; remove=true)
    println("Paths after removal : $(sol.bundlePaths)")
    # println(sol.bundlesOnNode)
    # println(sol.bins)
    I, J, V = findnz(sol.bins)
    println("Bins after refilling : \n $I \n $J \n $V")
    @test costAdded + costRemoved ≈ 0.0
    @test sol.bundlePaths == emptySol.bundlePaths
    @test sol.bundlesOnNode == emptySol.bundlesOnNode
    OFOND.clean_empty_bins!(sol, instance)
    @test sol.bins == emptySol.bins
end