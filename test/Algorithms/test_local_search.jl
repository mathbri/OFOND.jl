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
    OFOND.greedy!(sol, instance)
    greedySol = deepcopy(sol)
    # remove bundle 1 with cost removed = 0 so nothing happens
    OFOND.bundle_reintroduction!(sol, instance, bundle1)
    @test sol == greedySol
    # check with save_and_remove_bundle function
    otherSol = deepcopy(sol)
    oldBins, costRemoved = save_and_remove_bundle!(
        otherSol, instance, [bundle1], [sol.bundlePaths[1]]
    )
    @test costRemoved <= EPS

    # remove bundle 3, has the same path so added = removed
    OFOND.bundle_reintroduction!(sol, instance, bundle1)
    @test sol == greedySol
    #  check with save_and_remove_bundle and greedy_insertion
    otherSol = deepcopy(sol)
    oldBins, costRemoved = save_and_remove_bundle!(
        otherSol, instance, [bundle1], [sol.bundlePaths[1]]
    )
    @test costRemoved > EPS
    pathCost, newPath = greedy_insertion(
        otherSol, TTGraph, TSGraph, bundle1, supp1FromDel2, plantFromDel0
    )
    @test costRemoved ≈ pathCost
    @test newPath == sol.bundlePaths[1]

    # change path bundle 3 
    OFOND.update_solution!(sol, instance, [bundle3]; remove=true)
    OFOND.update_solution!(sol, instance, [bundle3], [TTPath])
    # adding commodities si that the filling is different after reinsertion
    OFOND.add!(sol.bins[xdockStep4, plantStep1][1], commodity3)
    OFOND.add!(sol.bins[supp1Step3, xdockStep4][1], commodity3)
    @test sol.bins[supp1Step3, xdockStep4] ==
        [OFOND.Bin(0, 50, [commodity1, commodity1, commodity2, commodity1, commodity3])]
    @test sol.bins[xdockStep4, plantStep1] ==
        [OFOND.Bin(0, 50, [commodity1, commodity1, commodity2, commodity1, commodity3])]
    # reinsert, has the same previous path
    OFOND.bundle_reintroduction!(sol, instance, bundle3)
    # and the filling is different on those shared with bundle 1 
    @test sol.bundlePaths == greedySol.bundlePaths
    @test sol.bins[supp1Step3, xdockStep4] ==
        [OFOND.Bin(0, 50, [commodity1, commodity1, commodity3, commodity2, commodity1])]
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
    OFOND.two_node_incremental!(sol, instance, supp1FromDel3, plantFromDel0)
    # paths back to greedy
    greedySol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.greedy!(greedySol, instance)
    @test sol == greedySol
    # TODO : with, by having old path cheapest in lb insertion, how exactly ?
    # if both_insertion and change_solution_to_other works fine should be good 
    # but should be great to test this too
end

# @testset "Local search (full)" begin
#     # TODO : mix of the above, from bad solution to good
# end