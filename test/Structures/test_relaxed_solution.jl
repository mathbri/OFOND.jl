# Define TravelTimeGraph and TimeSpaceGraph
TTGraph = OFOND.TravelTimeGraph(network, bundles)
xdockIdxs = findall(n -> n == xdock, TTGraph.networkNodes)
portIdxs = findall(n -> n == port_l, TTGraph.networkNodes)
plantIdxs = findall(n -> n == plant, TTGraph.networkNodes)
common = vcat(xdockIdxs, portIdxs, plantIdxs)
TSGraph = OFOND.TimeSpaceGraph(network, 4)
allNodes = vcat(
    fill(supplier1, 4), fill(supplier2, 4), fill(xdock, 4), fill(port_l, 4), fill(plant, 4)
)
allSteps = repeat([1, 2, 3, 4], 5)
allIdxs = [
    TSGraph.hashToIdx[hash(step, node.hash)] for (step, node) in zip(allSteps, allNodes)
]

@testset "Construction" begin
    # With different bundles and solutions, construct different relaxed solutions
    # Empty solution and all bundles
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    relaxedSol = OFOND.RelaxedSolution(sol, instance, bundles)
    @test relaxedSol.bundleIdxs == [1, 2, 3]
    @test relaxedSol.bundlePaths == [[-1, -1], [-1, -1], [-1, -1]]
    @test nnz(relaxedSol.loads) == length(TSGraph.commonArcs)
    @testset "empty load content" for (src, dst) in TSGraph.commonArcs
        @test relaxedSol.loads[src, dst] == 0
    end

    # Non-empty solution and some bundles
    OFOND.add_path!(sol, bundle1, TTPath)
    OFOND.add_path!(sol, bundle2, [xdockFromDel2, portFromDel1])
    push!(sol.bins[xdockStep3, portStep4], OFOND.Bin(20, 30, [commodity2, commodity1]))
    push!(sol.bins[xdockStep3, portStep4], OFOND.Bin(20, 30, [commodity2, commodity1]))
    push!(sol.bins[portStep4, plantStep1], OFOND.Bin(15, 5, [commodity3]))
    relaxedSol = OFOND.RelaxedSolution(sol, instance, [bundle1, bundle2])
    @test relaxedSol.bundleIdxs == [1, 2]
    @test relaxedSol.bundlePaths == [TTPath, [xdockFromDel2, portFromDel1]]
    @test nnz(relaxedSol.loads) == length(TSGraph.commonArcs)
    @testset "non-empty load content" for (src, dst) in TSGraph.commonArcs
        if src == xdockStep3 && dst == portStep4
            @test relaxedSol.loads[src, dst] == 60
        elseif src == portStep4 && dst == plantStep1
            @test relaxedSol.loads[src, dst] == 5
        else
            @test relaxedSol.loads[src, dst] == 0
        end
    end
end