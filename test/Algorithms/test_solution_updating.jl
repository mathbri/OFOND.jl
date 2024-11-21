@testset "is path partial" begin
    @test !OFOND.is_path_partial(TTGraph, bundle1, TTPath)
    TTPath2 = TTPath[2:end]
    @test OFOND.is_path_partial(TTGraph, bundle1, TTPath2)
    TTPath3 = TTPath[1:(end - 1)]
    @test OFOND.is_path_partial(TTGraph, bundle1, TTPath3)
end

supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]

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
    @test costAdded1 ≈ costAdded2 ≈ 20.4
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

xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
TTPath1 = [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]

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
        TSGraph, TTGraph, [bundle1, bundle3], [TTPath1, TTPath1]
    )
    I, J, V = findnz(binsUpdated)
    @test I == [supp1Step2, supp1Step3, xdockStep4, xdockStep3, portStep4, portStep1]
    @test J == [xdockStep3, xdockStep4, portStep1, portStep4, plantStep1, plantStep2]
    @test V == fill(true, 6)
end

supp3FromDel3 = TTGraph.hashToIdx[hash(3, supplier3.hash)]
TTPath3 = [supp3FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]

supp3Step2 = TSGraph.hashToIdx[hash(2, supplier3.hash)]
supp3Step3 = TSGraph.hashToIdx[hash(3, supplier3.hash)]

sol = OFOND.Solution(TTGraph, TSGraph, bundles)
OFOND.add_bundle!(sol, instance, bundle3, TTPath3)
# modify bins for the refill bins to actually do something
I = [supp3Step2, xdockStep3, portStep4, supp3Step3, xdockStep4, portStep1]
J = [xdockStep3, portStep4, plantStep1, xdockStep4, portStep1, plantStep2]
for (i, j) in zip(I, J)
    push!(sol.bins[i, j], OFOND.Bin(15, 5, [commodity3]))
end

ALL_COMMODITIES = OFOND.Commodity[]

@testset "refill bins" begin
    # first is closely related to bin packing
    bins = [
        OFOND.Bin(10, 10, [commodity1]),
        OFOND.Bin(5, 15, [commodity1, commodity3]),
        OFOND.Bin(5, 15, [commodity2]),
    ]
    newBins = OFOND.refill_bins!(bins, 20, ALL_COMMODITIES)
    @test length(bins) == 2
    @test newBins == -1
    @test bins == [
        OFOND.Bin(0, 20, [commodity2, commodity3]),
        OFOND.Bin(0, 20, [commodity1, commodity1]),
    ]
    bins = fill(OFOND.Bin(20), 3)
    newBins = OFOND.refill_bins!(bins, 20, ALL_COMMODITIES)
    @test newBins == -3
    @test bins == OFOND.Bin[]

    # other is to check that that this refilling is done on every arcs stated in working arcs
    binsUpdated = OFOND.get_bins_updated(TSGraph, TTGraph, [bundle3], [TTPath3])
    costAdded = OFOND.refill_bins!(sol, TSGraph, binsUpdated, ALL_COMMODITIES)
    # linear costs didn't but cost reduced by 4 * 4.0 = 16.0, 1 bin per consolidated arcs
    @test costAdded ≈ -16.0
    # linear arcs not refilled
    @test sol.bins[supp3Step2, xdockStep3] ==
        [OFOND.Bin(27, 25, [commodity2, commodity1]), OFOND.Bin(15, 5, [commodity3])]
    @test sol.bins[supp3Step3, xdockStep4] ==
        [OFOND.Bin(27, 25, [commodity2, commodity1]), OFOND.Bin(15, 5, [commodity3])]
    # consolidated arcs refilled 
    @test sol.bins[portStep4, plantStep1] ==
        [OFOND.Bin(20, 30, [commodity2, commodity1, commodity3])]
    @test sol.bins[portStep1, plantStep2] ==
        [OFOND.Bin(20, 30, [commodity2, commodity1, commodity3])]
    @test sol.bins[xdockStep3, portStep4] ==
        [OFOND.Bin(20, 30, [commodity2, commodity1, commodity3])]
    @test sol.bins[xdockStep4, portStep1] ==
        [OFOND.Bin(20, 30, [commodity2, commodity1, commodity3])]

    # testing shortcut for direct arcs (emptied and not recomputed)
    push!(sol.bins[supp1Step3, plantStep1], OFOND.Bin(20, 30, [commodity2, commodity1]))
    binsUpdated = OFOND.get_bins_updated(
        TSGraph, TTGraph, [bundle1], [[supp1FromDel2, plantFromDel0]]
    )
    costAdded = OFOND.refill_bins!(sol, TSGraph, binsUpdated, ALL_COMMODITIES)
    @test costAdded ≈ -10.0
    # arc emptied
    @test sol.bins[supp1Step3, plantStep1] == OFOND.Bin[]
    # push it back again
    push!(sol.bins[supp1Step3, plantStep1], OFOND.Bin(20, 30, [commodity2, commodity1]))
    costAdded = OFOND.refill_bins!(
        sol, TTGraph, TSGraph, bundle1, [supp1FromDel2, plantFromDel0], ALL_COMMODITIES
    )
    @test costAdded ≈ -10.0
    # arc emptied
    @test sol.bins[supp1Step3, plantStep1] == OFOND.Bin[]
end

sol = OFOND.Solution(TTGraph, TSGraph, bundles)
OFOND.add_bundle!(sol, instance, bundle3, TTPath3)
I = [supp3Step2, xdockStep3, portStep4, supp3Step3, xdockStep4, portStep1]
J = [xdockStep3, portStep4, plantStep1, xdockStep4, portStep1, plantStep2]
for (i, j) in zip(I, J)
    push!(sol.bins[i, j], OFOND.Bin(15, 5, [commodity3]))
end

@testset "remove bundle" begin
    # test with empty, partial and normal path
    # empty and full path should be the same
    sol2 = deepcopy(sol)
    costAdded2, oldPart2 = OFOND.remove_bundle!(sol2, instance, bundle3, Int[])
    sol3 = deepcopy(sol)
    costAdded3, oldPart3 = OFOND.remove_bundle!(sol3, instance, bundle3, TTPath3)
    # test that commodities are not in the bins but the bins are still there
    emptySol = OFOND.Solution(TTGraph, TSGraph, bundles)
    @test costAdded2 ≈ costAdded3 ≈ -41.34615384615385
    @test oldPart2 == oldPart3 == TTPath3
    @test sol2.bundlePaths == sol3.bundlePaths == emptySol.bundlePaths
    @test sol2.bundlesOnNode == sol3.bundlesOnNode == emptySol.bundlesOnNode
    @test sol2.bins == sol3.bins
    V2 = findnz(sol2.bins)[3]
    filteredV2 = filter(x -> length(x) > 0, V2)
    V3 = findnz(sol3.bins)[3]
    filteredV3 = filter(x -> length(x) > 0, V3)
    @test all(
        bins -> bins == [OFOND.Bin(52), OFOND.Bin(15, 5, [commodity3])], filteredV2[1:2]
    )
    @test all(
        bins -> bins == [OFOND.Bin(50), OFOND.Bin(15, 5, [commodity3])], filteredV2[3:end]
    )
    # tests with partial path
    sol4 = deepcopy(sol)
    costAdded4, oldPart4 = OFOND.remove_bundle!(
        sol4, instance, bundle3, [supp3FromDel3, xdockFromDel2, portFromDel1]
    )
    @test costAdded4 ≈ -28.346153846153847
    @test oldPart4 == [supp3FromDel3, xdockFromDel2, portFromDel1]
    @test sol4.bundlePaths ==
        [[-1, -1], [-1, -1], [supp3FromDel3, portFromDel1, plantFromDel0]]
    @test sol4.bundlesOnNode[xdockFromDel2] == Int[]
    @test sol4.bundlesOnNode[portFromDel1] == [3]
    @test sol4.bins[xdockStep3, portStep4] ==
        [OFOND.Bin(50), OFOND.Bin(15, 5, [commodity3])]
    @test sol4.bins[portStep4, plantStep1] ==
        [OFOND.Bin(25, 25, [commodity2, commodity1]), OFOND.Bin(15, 5, [commodity3])]
end

sol = OFOND.Solution(TTGraph, TSGraph, bundles)
sol2 = OFOND.Solution(TTGraph, TSGraph, bundles)
sol3 = OFOND.Solution(TTGraph, TSGraph, bundles)
emptySol = OFOND.Solution(TTGraph, TSGraph, bundles)

@testset "update solution" begin
    # testing equality between modes of updating 
    # all at once   
    costAdded = OFOND.update_solution!(
        sol, instance, [bundle1, bundle3], [TTPath1, TTPath3]
    )
    @test sol.bundlePaths == [TTPath1, [-1, -1], TTPath3]
    # one at a time 
    costAdded2 = OFOND.update_solution!(sol2, instance, [bundle1], [TTPath1])
    costAdded3 = OFOND.update_solution!(sol3, instance, bundle1, TTPath1)
    @test costAdded2 ≈ costAdded3
    @test sol2.bundlePaths == sol3.bundlePaths
    @test sol2.bins == sol3.bins
    costAdded2 += OFOND.update_solution!(sol2, instance, [bundle3], [TTPath3])
    costAdded3 += OFOND.update_solution!(sol3, instance, bundle3, TTPath3)
    @test costAdded2 ≈ costAdded3
    @test costAdded ≈ costAdded3
    @test sol2.bundlePaths == sol3.bundlePaths
    @test sol2.bins == sol3.bins
    @test sol2.bundlePaths == sol.bundlePaths
    @test sol2.bins == sol.bins
    # removing and seeing return to initial state
    costRemoved = OFOND.update_solution!(sol, instance, [bundle1, bundle3]; remove=true)
    @test -costAdded ≈ costRemoved
    @test sol.bundlePaths == emptySol.bundlePaths
    @test sol.bundlesOnNode == emptySol.bundlesOnNode
    OFOND.clean_empty_bins!(sol, instance)
    @test sol.bins == emptySol.bins
end

@testset "clean empty bins" begin
    sol = deepcopy(emptySol)
    push!(sol.bins[supp1Step2, xdockStep3], OFOND.Bin(20, 0, OFOND.Commodity[]))
    push!(sol.bins[xdockStep3, portStep4], OFOND.Bin(20, 0, OFOND.Commodity[]))
    push!(sol.bins[portStep4, plantStep1], OFOND.Bin(15, 5, [commodity3]))
    OFOND.clean_empty_bins!(sol, instance)
    I, J, V = findnz(sol.bins)
    nonEmpty = findall(x -> length(x) > 0, V)
    @test I[nonEmpty] == [portStep4]
    @test J[nonEmpty] == [plantStep1]
    @test V[nonEmpty] == [[OFOND.Bin(15, 5, [commodity3])]]

    sol = deepcopy(emptySol)
    push!(sol.bins[supp1Step2, xdockStep3], OFOND.Bin(20, 0, OFOND.Commodity[]))
    push!(sol.bins[xdockStep3, portStep4], OFOND.Bin(20, 0, OFOND.Commodity[]))
    push!(sol.bins[portStep4, plantStep1], OFOND.Bin(15, 5, OFOND.Commodity[]))
    OFOND.clean_empty_bins!(sol, instance)
    I, J, V = findnz(sol.bins)
    nonEmpty = findall(x -> length(x) > 0, V)
    @test I[nonEmpty] == [portStep4]
    @test J[nonEmpty] == [plantStep1]
    @test V[nonEmpty] == [[OFOND.Bin(15, 5, OFOND.Commodity[])]]
end