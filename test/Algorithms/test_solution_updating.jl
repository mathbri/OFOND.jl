@testset "is path partial" begin
    @test OFOND.is_path_partial(TTGraph, bundle1, TTPath)
    TTPath2 = TTPath[2:end]
    @test !OFOND.is_path_partial(TTGraph, bundle1, TTPath2)
    TTPath3 = TTPath[1:(end - 1)]
    @test !OFOND.is_path_partial(TTGraph, bundle1, TTPath3)
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
    costAdded = OFOND.add_bundle!(sol, instance, bundle1, [])
    @test costAdded ≈ 0.0
    @test length(sol.bundlePaths) == 0
    I, J, V = findnz(sol.bins)
    @test V == [Bin[] for _ in I]
    # add shortcut to form a second path and verify that both have the same updates 
    path1 = [supp1FromDel3, supp1FromDel2, plantFromDel0]
    costAdded1 = OFOND.add_bundle!(sol, instance, bundle1, path1)
    sol2 = OFOND.Solution(TTGraph, TSGraph, bundles)
    path2 = [supp1FromDel2, plantFromDel0]
    costAdded2 = OFOND.add_bundle!(sol2, instance, bundle1, path2)
    @test costAdded1 ≈ costAdded2 ≈ 0.0
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
        [supp1FromDel3, supp1FromDel2, 20, xdockFromDel1];
        skipFill=true,
    )
    @test costAdded ≈ 0.0
    @test sol.bundlePaths[1] == [supp1FromDel2, xdockFromDel1, 20, plantFromDel0]
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
        TTGraph, TSGraph, [bundle1, bundle3], [TTPath, TTPath]
    )
    I, J, V = findnz(binsUpdated)
    @test I == [supp1Step2, xdockStep3, portStep4, supp1Step3, xdockStep4, portStep1]
    @test J == [xdockStep3, portStep4, plantStep1, xdockStep4, portStep1, plantStep2]
    @test V == fill(true, 6)
end

sol = OFOND.Solution(TTGraph, TSGraph, bundles)
OFOND.add_bundle!(sol, instance, bundle3, TTPath)
# modify bins for the refill bins to actually do something
I == [supp1Step2, xdockStep3, portStep4, supp1Step3, xdockStep4, portStep1]
J == [xdockStep3, portStep4, plantStep1, xdockStep4, portStep1, plantStep2]
for (i, j) in zip(I, J)
    push!(sol.bins[i, j], OFOND.Bin(5, 15, [commodity3]))
end

@testset "refill bins" begin
    # first is closely related to bin packing
    bins = [
        Bin(10, 10, [commodity1]),
        Bin(5, 15, [commodity1, commodity3]),
        Bin(5, 15, [commodity2]),
    ]
    newBins = refill_bins!(bins, 20)
    @test length(bins) == 2
    @test newBins == -1
    @test bins ==
        [Bin(0, 20, [commodity2, commodity3]), Bin(0, 20, [commodity1, commodity1])]
    # other is to check that that this relling is done on every arcs stated in working arcs
    binsUpdated = OFOND.get_bins_updated(TTGraph, TSGraph, [bundle3], [TTPath])
    costAdded = OFOND.refill_bins!(sol, TSGraph, binsUpdated)
    @test costAdded ≈ 0.0
    V = findnz(sol.bins)[3]
    @test all(bins -> length(bins) == 1, V)
end

sol = OFOND.Solution(TTGraph, TSGraph, bundles)
OFOND.add_bundle!(sol, instance, bundle3, TTPath)
I == [supp1Step2, xdockStep3, portStep4, supp1Step3, xdockStep4, portStep1]
J == [xdockStep3, portStep4, plantStep1, xdockStep4, portStep1, plantStep2]
for (i, j) in zip(I, J)
    push!(sol.bins[i, j], OFOND.Bin(5, 15, [commodity3]))
end

@testset "remove bundle" begin
    # test with empty, partial and normal path
    # empty and full path should be the same
    sol2 = deepcopy(sol)
    costAdded2 = OFOND.remove_bundle!(sol2, instance, bundle3)
    sol3 = deepcopy(sol)
    costAdded3 = OFOND.remove_bundle!(sol3, instance, bundle3, TTPath)
    # test that commodities are not in the bins but the bins are still there
    emptySol = OFOND.Solution(TTGraph, TSGraph, bundles)
    @test costAdded2 ≈ costAdded3 ≈ 0.0
    @test sol2.bundlePaths == sol3.bundlePaths == emptySol.bundlePaths
    @test sol2.bundlesOnNode == sol3.bundlesOnNode == emptySol.bundlesOnNode
    @test sol2.bins == sol3.bins
    V2 = findnz(sol2.bins)[3]
    V3 = findnz(sol3.bins)[3]
    @test all(bins -> bins == [Bin(50), OFOND.Bin(5, 15, [commodity3])], V2)
    @test all(bins -> bins == [Bin(50), OFOND.Bin(5, 15, [commodity3])], V3)
end

sol = OFOND.Solution(TTGraph, TSGraph, bundles)
emptySol = OFOND.Solution(TTGraph, TSGraph, bundles)

@testset "update solution" begin
    # mix of all the above
    costAdded = OFOND.update_solution!(sol, instance, [bundle1, bundle3], [TTPath, TTPath])
    @test sol.bundlePaths == [TTPath, [-1, -1], TTPath]
    costRemoved = OFOND.update_solution!(
        emptySol, instance, [bundle1, bundle3]; remove=true
    )
    @test costAdded + costRemoved ≈ 0.0
    @test sol == emptySol
end