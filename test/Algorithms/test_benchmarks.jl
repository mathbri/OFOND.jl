supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]
supp2fromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]

supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
supp3Step3 = TSGraph.hashToIdx[hash(3, supplier3.hash)]
supp2Step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]

supp3Step4 = TSGraph.hashToIdx[hash(4, supplier3.hash)]
plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]

@testset "Shortest Delivery" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.shortest_delivery!(sol, instance)
    # all bundles have direct paths
    @test sol.bundlePaths == [
        [supp1FromDel2, plantFromDel0],
        [supp2fromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    # only the plant has bundle on nodes
    @test sol.bundlesOnNode[plantFromDel0] == [1, 2, 3]
    otherBundlesOnNode = filter(p -> p.first != plantFromDel0, sol.bundlesOnNode)
    @test all(p -> length(p.second) == 0, otherBundlesOnNode)
    # bins should be filled accordingly
    @test sol.bins[supp1Step3, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[supp2Step4, plantStep1] == [OFOND.Bin(21, 30, [commodity2, commodity2])]
    @test sol.bins[supp3Step3, plantStep1] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    @test sol.bins[supp3Step4, plantStep2] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    I, J, V = findnz(sol.bins)
    # test equivalent to : all other arcs don't have bins
    @test sum(x -> length(x), V) == 4
end