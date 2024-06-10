@testset "Bin packing improvement" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.add_order!(sol, TSGraph, TSPath, order1)
    # add commodities so that this neighborhood change things
    push!(sol.bins[supp1Step2, xdockStep3], OFOND.Bin(50))
    push!(sol.bins[xdockStep3, portStep4], OFOND.Bin(45, 5, [commodity3]))
    # test with skipLinear
    costImprov = OFOND.bin_packing_improvement!(sol, instance)
    @test costImprov ≈ 4.0
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

@testset "Bundle reintroduction" begin
    # take greedy solution 
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # lower bound and greedy give the same solution but for greedy we need to adapt properties
    OFOND.lower_bound!(sol, instance)
    greedySol = deepcopy(sol)
    # remove bundle 1 with cost removed = 0 so nothing happens
    costImprov = OFOND.bundle_reintroduction!(sol, instance, bundle1)
    @test sol.bundlePaths == greedySol.bundlePaths
    @test costImprov ≈ 0.0
    # bundle1 and 3 are equal for the operator so when filtering bundel on nodes, bundle3 is also deleted but just bundle 1 is added back
    # also because of deletion and reinsertion, the order is now different in the vector
    # @test sol.bundlesOnNode == greedySol.bundlesOnNode
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
    costImprov = OFOND.bundle_reintroduction!(sol, instance, bundle2)
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
    @test costRemoved < -1e-5
    supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
    newPath, pathCost = OFOND.greedy_insertion(
        otherSol, TTGraph, TSGraph, bundle2, supp2FromDel1, plantFromDel0
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
    costImprov = OFOND.bundle_reintroduction!(sol, instance, bundle3)
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

@testset "Two node incremental" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # put bundle 1 and 3 on TTPath
    OFOND.update_solution!(sol, instance, [bundle1, bundle3], [TTPath, TTPath])
    OFOND.update_solution!(sol, instance, [bundle2], [[supp2fromDel1, plantFromDel0]])
    # play with current cost so that lower boud insertion or greedy insertion is better
    # without, same prop so that greedy insertion is better

    # no bundlesOnNode for a supplier 
    # TODO : add 2 xdocks so that you can change the path 

    # OFOND.two_node_incremental!(sol, instance, supp1FromDel3, plantFromDel0)
    # # paths back to greedy
    # greedySol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # OFOND.greedy!(greedySol, instance)
    # @test sol == greedySol

    # TODO : with, by having old path cheapest in lb insertion, how exactly ?
    # if both_insertion and change_solution_to_other works fine should be good 
    # but should be great to test this too
end

# @testset "Local search (full)" begin
#     # TODO : mix of the above, from bad solution to good
# end