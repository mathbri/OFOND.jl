TSGraph = OFOND.TimeSpaceGraph(network, 4)

allNodes = vcat(
    fill(supplier1, 4), fill(supplier2, 4), fill(xdock, 4), fill(port_l, 4), fill(plant, 4)
)
allSteps = repeat([1, 2, 3, 4], 5)
allIdxs = [
    TSGraph.hashToIdx[hash(step, node.hash)] for (step, node) in zip(allSteps, allNodes)
]

supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
supp2Step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]

@testset "Slope Sclaling" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # from empty current cost to unit costs
    I, J, V = findnz(TSGraph.currentCost)
    @test all(x -> x == 1e-5, V)
    OFOND.slope_scaling_cost_update!(TSGraph, sol)
    I = vcat(
        allIdxs[1:4],
        allIdxs[1:4],
        allIdxs[5:8],
        allIdxs[5:8],
        allIdxs[9:12],
        allIdxs[9:12],
        allIdxs[13:16],
    )
    J = vcat(
        allIdxs[[10, 11, 12, 9]],
        allIdxs[[19, 20, 17, 18]],
        allIdxs[[10, 11, 12, 9]],
        allIdxs[[18, 19, 20, 17]],
        allIdxs[[14, 15, 16, 13]],
        allIdxs[[18, 19, 20, 17]],
        allIdxs[[18, 19, 20, 17]],
    )
    V = vcat(fill(4.0, 4), fill(10.0, 4), fill(4.0, 4), fill(10.0, 4), fill(4.0, 12))
    @test [TSGraph.currentCost[i, j] for (i, j) in zip(I, J)] == V
    # add some commodities (fill half of volume on supp1_to_plant to see x2 cost update)
    push!(sol.bins[supp1Step3, plantStep1], OFOND.Bin(25, 25, [commodity1, commodity2]))
    OFOND.slope_scaling_cost_update!(TSGraph, sol)
    # check the new current costs for those arc and the no update for the other
    V = vcat(
        fill(4.0, 4), [10.0, 10.0, 20.0, 10.0], fill(4.0, 4), fill(10.0, 4), fill(4.0, 12)
    )
    @test [TSGraph.currentCost[i, j] for (i, j) in zip(I, J)] == V
end

xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]
supp1Step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
supp2Step3 = TSGraph.hashToIdx[hash(3, supplier2.hash)]
supp2Step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]

supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]

TTPath = [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]

supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]

@testset "Compute current load" begin
    # Empty solution
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.update_solution!(sol, instance, bundle11, [supp1FromDel2, plantFromDel0])
    OFOND.update_solution!(sol, instance, bundle22, [supp2FromDel1, plantFromDel0])
    OFOND.update_solution!(sol, instance, bundle33, [supp3FromDel2, plantFromDel0])
    testLoad = map(arc -> 0, TSGraph.networkArcs)
    @test OFOND.compute_loads(instance, sol, [1, 2, 3], sol.bundlePaths) == testLoad
    # Non-empty loads
    testLoad[supp1Step3, plantStep1] = 20
    @test OFOND.compute_loads(instance, sol, [2, 3], sol.bundlePaths[[2, 3]]) == testLoad
    testLoad[supp2Step4, plantStep1] = 30
    @test OFOND.compute_loads(instance, sol, [3], sol.bundlePaths[[3]]) == testLoad
end

supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]
supp2FromDel2 = TTGraph.hashToIdx[hash(2, supplier2.hash)]

supp3Step3 = TSGraph.hashToIdx[hash(3, supplier3.hash)]
supp3Step4 = TSGraph.hashToIdx[hash(4, supplier3.hash)]
xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]
plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]

@testset "ArcFlow and TSN perturbations" begin
    # Take lower bound solution 
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.update_solution!(
        sol, instance, bundle11, [supp1FromDel2, xdockFromDel1, plantFromDel0]
    )
    OFOND.update_solution!(sol, instance, bundle22, [supp2FromDel1, plantFromDel0])
    OFOND.update_solution!(
        sol, instance, bundle33, [supp3FromDel2, xdockFromDel1, plantFromDel0]
    )
    # test creating different arc flow perturbations
    pert1 = OFOND.arc_flow_perturbation(instance, sol, [1])
    @test pert1.type == :arc_flow
    @test pert1.bundleIdxs == [1]
    @test pert1.src == 0
    @test pert1.dst == 0
    @test pert1.oldPaths == [[supp1FromDel2, xdockFromDel1, plantFromDel0]]
    @test pert1.newPaths == Vector{Int}[]
    testLoad = map(arc -> 0, TSGraph.networkArcs)
    testLoad[supp2Step4, plantStep1] = 30
    testLoad[supp3Step3, xdockStep4] = 25
    testLoad[xdockStep4, plantStep1] = 25
    testLoad[supp3Step4, xdockStep1] = 25
    testLoad[xdockStep1, plantStep2] = 25
    @test pert1.loads == testLoad
    pert2 = OFOND.arc_flow_perturbation(instance, sol, [1, 2])
    @test pert2.type == :arc_flow
    @test pert2.bundleIdxs == [1, 2]
    @test pert2.src == 0
    @test pert2.dst == 0
    @test pert2.oldPaths ==
        [[supp1FromDel2, xdockFromDel1, plantFromDel0], [supp2FromDel1, plantFromDel0]]
    @test pert2.newPaths == Vector{Int}[]
    testLoad = map(arc -> 0, TSGraph.networkArcs)
    testLoad[supp3Step3, xdockStep4] = 25
    testLoad[xdockStep4, plantStep1] = 25
    testLoad[supp3Step4, xdockStep1] = 25
    testLoad[xdockStep1, plantStep2] = 25
    @test pert2.loads == testLoad
    pert3 = OFOND.arc_flow_perturbation(instance, sol, [2, 3])
    @test pert3.type == :arc_flow
    @test pert3.bundleIdxs == [2, 3]
    @test pert3.src == 0
    @test pert3.dst == 0
    @test pert3.oldPaths ==
        [[supp2FromDel1, plantFromDel0], [supp3FromDel2, xdockFromDel1, plantFromDel0]]
    @test pert3.newPaths == Vector{Int}[]
    testLoad = map(arc -> 0, TSGraph.networkArcs)
    testLoad[supp1Step3, xdockStep4] = 20
    testLoad[xdockStep4, plantStep1] = 20
    @test pert3.loads == testLoad
    # test creating different perturbations
    pert4 = OFOND.two_shared_node_perturbation(instance, sol, xdockFromDel1, plantFromDel0)
    @test pert4.type == :two_shared_node
    @test pert4.bundleIdxs == [1, 3]
    @test pert4.src == xdockFromDel1
    @test pert4.dst == plantFromDel0
    @test pert4.oldPaths == [[xdockFromDel1, plantFromDel0], [xdockFromDel1, plantFromDel0]]
    @test pert4.newPaths == Vector{Int}[]
    testLoad = map(arc -> 0, TSGraph.networkArcs)
    testLoad[supp1Step3, xdockStep4] = 20
    testLoad[supp3Step3, xdockStep4] = 25
    testLoad[supp3Step4, xdockStep1] = 25
    testLoad[supp2Step4, plantStep1] = 30
    @test pert4.loads == testLoad
end

xdockFromDel0 = TTGraph.hashToIdx[hash(0, xdock.hash)]
supp1FromDel1 = TTGraph.hashToIdx[hash(1, supplier1.hash)]

@testset "New path generation" begin
    # attract path generation (and limit cases)
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    path = OFOND.generate_attract_path(instance, sol, bundle1, xdockFromDel0, xdockFromDel1)
    @test path == [supp1FromDel1, xdockFromDel0, xdockFromDel1, plantFromDel0]
    path = OFOND.generate_attract_path(instance, sol, bundle2, xdockFromDel0, xdockFromDel1)
    @test path == [supp2FromDel1, xdockFromDel0, xdockFromDel1, plantFromDel0]
    path = OFOND.generate_attract_path(instance, sol, bundle1, xdockFromDel1, plantFromDel0)
    @test path == [supp1FromDel2, xdockFromDel1, plantFromDel0]
    path = OFOND.generate_attract_path(instance, sol, bundle2, xdockFromDel1, plantFromDel0)
    @test path == [supp2FromDel2, xdockFromDel1, plantFromDel0]
    # reduce path generation
    path = OFOND.generate_reduce_path(instance, sol, bundle1, xdockFromDel1, plantFromDel0)
    @test path == [supp1FromDel2, plantFromDel0]
    path = OFOND.generate_reduce_path(instance, sol, bundle2, xdockFromDel1, plantFromDel0)
    @test path == [supp2FromDel1, plantFromDel0]
end

@testset "Path flow perturbation" begin
    # Take lower bound solution 
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.update_solution!(
        sol, instance, bundle11, [supp1FromDel2, xdockFromDel1, plantFromDel0]
    )
    OFOND.update_solution!(sol, instance, bundle22, [supp2FromDel1, plantFromDel0])
    OFOND.update_solution!(
        sol, instance, bundle33, [supp3FromDel2, xdockFromDel1, plantFromDel0]
    )
    # test creating different perturbations
    pert5 = OFOND.path_flow_perturbation(instance, sol, xdockFromDel1, plantFromDel0)
    @test pert5.type == :attract_reduce
    @test pert5.bundleIdxs == [1, 2, 3]
    @test pert5.src == 0
    @test pert5.dst == 0
    @test pert5.oldPaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    # reduce for 1 and 3 and attract for 2
    @test pert5.newPaths == [
        [supp1FromDel2, plantFromDel0],
        [supp2FromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    testLoad = map(arc -> 0, TSGraph.networkArcs)
    @test pert5.loads == testLoad
end

@testset "Bundle selection" begin
    # MaxVar used to select the bundle we want
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.update_solution!(
        sol, instance, bundle11, [supp1FromDel2, xdockFromDel1, plantFromDel0]
    )
    OFOND.update_solution!(sol, instance, bundle22, [supp2FromDel1, plantFromDel0])
    OFOND.update_solution!(
        sol, instance, bundle33, [supp3FromDel2, xdockFromDel1, plantFromDel0]
    )
    # plant neighborhoods
    @test OFOND.select_bundles_by_plant(instance; maxVar=16) == [2]
    @test OFOND.select_bundles_by_plant(instance; maxVar=19) in [[2], [1], [3]]
    @test sort(OFOND.select_bundles_by_plant(instance; maxVar=23)) in [[1, 2], [2, 3]]
    @test sort(OFOND.select_bundles_by_plant(instance; maxVar=30)) == [1, 2, 3]
    # supplier neighborhoods
    @test OFOND.select_bundles_by_supplier(instance; maxVar=16) == [2]
    @test OFOND.select_bundles_by_supplier(instance; maxVar=19) in [[2], [1], [3]]
    @test sort(OFOND.select_bundles_by_supplier(instance; maxVar=23)) in [[1, 2], [2, 3]]
    @test sort(OFOND.select_bundles_by_supplier(instance; maxVar=30)) == [1, 2, 3]
    # random neighborhoods
    @test OFOND.select_random_bundles(instance; maxVar=16) == [2]
    @test OFOND.select_random_bundles(instance; maxVar=19) in [[2], [1], [3]]
    @test sort(OFOND.select_random_bundles(instance; maxVar=23)) in [[1, 2], [2, 3]]
    @test sort(OFOND.select_random_bundles(instance; maxVar=30)) == [1, 2, 3]
    # For two shared node, find the thrashold that makes only one tuple available 
    src, dst, bunIdxs = OFOND.select_bundles_by_two_node(instance, sol, 1.0)
    @test src == xdockFromDel1
    @test dst == plantFromDel0
    @test bunIdxs == [1, 3]
    src, dst, bunIdxs = OFOND.select_bundles_by_two_node(instance, sol, 1000.0)
    @test src == xdockFromDel1
    @test dst == plantFromDel0
    @test bunIdxs == [1, 3]
end

@testset "Arc selection" begin
    # select_common_arc
    arcsSelected = [OFOND.select_common_arc(instance) for _ in 1:50]
    @test all(
        a -> TTGraph.networkArcs[a[1], a[2]].type in OFOND.COMMON_ARC_TYPES, arcsSelected
    )
end

supp3FromDel3 = TTGraph.hashToIdx[hash(3, supplier3.hash)]

@testset "Get perturbation" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.update_solution!(
        sol, instance, bundle11, [supp1FromDel2, xdockFromDel1, plantFromDel0]
    )
    OFOND.update_solution!(sol, instance, bundle22, [supp2FromDel1, plantFromDel0])
    OFOND.update_solution!(
        sol, instance, bundle33, [supp3FromDel2, xdockFromDel1, plantFromDel0]
    )
    # testing the 3 different arc flow perturbations
    pert1 = OFOND.get_perturbation(:single_plant, instance, sol)
    pert2 = OFOND.get_perturbation(:suppliers, instance, sol)
    pert3 = OFOND.get_perturbation(:random, instance, sol)
    testLoad = map(arc -> 0, TSGraph.networkArcs)
    @testset "pert $i" for (i, pert) in enumerate([pert1, pert2, pert3])
        @test pert.type == :arc_flow
        @test sort(pert.bundleIdxs) == [1, 2, 3]
        @test pert.src == pert.dst == 0
        @test pert.oldPaths[sortperm(pert.bundleIdxs)] == [
            [supp1FromDel2, xdockFromDel1, plantFromDel0],
            [supp2FromDel1, plantFromDel0],
            [supp3FromDel2, xdockFromDel1, plantFromDel0],
        ]
        @test pert.newPaths == Vector{Int}[]
        @test pert.loads == testLoad
    end
    # 1 possibility for two node
    pert4 = OFOND.get_perturbation(:two_shared_node, instance, sol)
    @test pert4.type == :two_shared_node
    @test pert4.bundleIdxs == [1, 3]
    @test pert4.src == xdockFromDel1
    @test pert4.dst == plantFromDel0
    @test pert4.oldPaths == [[xdockFromDel1, plantFromDel0], [xdockFromDel1, plantFromDel0]]
    @test pert4.newPaths == Vector{Int}[]
    testLoad = map(arc -> 0, TSGraph.networkArcs)
    testLoad[supp1Step3, xdockStep4] = 20
    testLoad[supp3Step3, xdockStep4] = 25
    testLoad[supp3Step4, xdockStep1] = 25
    testLoad[supp2Step4, plantStep1] = 30
    @test pert4.loads == testLoad
    # 5 possibilities so testing if it is either of those
    pert5 = OFOND.get_perturbation(:attract_reduce, instance, sol)
    @test pert5.type == :attract_reduce
    @test pert5.bundleIdxs == [1, 2, 3]
    @test pert5.src == 0
    @test pert5.dst == 0
    @test pert5.oldPaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    # If common arc = xdockFromDel3 -> portFromDel2 or xdockFromDel1 -> portFromDel0 (no paths possible)
    newPaths1 = [
        [supp1FromDel2, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    # If common arc = xdockFromDel2 -> portFromDel1 or portFromDel1 -> plantFromDel0
    TTPath3 = [supp3FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]
    newPaths2 = [TTPath, [supp2FromDel1, plantFromDel0], TTPath3]
    # If common arc = xdockFromDel1 - plantFromDel0
    newPaths3 = [
        [supp1FromDel2, plantFromDel0],
        [supp2FromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    @test pert5.newPaths in [newPaths1, newPaths2, newPaths3]
    testLoad = map(arc -> 0, TSGraph.networkArcs)
    @test pert5.loads == testLoad
end

supp1FromDel1 = TTGraph.hashToIdx[hash(1, supplier1.hash)]

@testset "Is outsource or direct (or shortcut)" begin
    # oursource direct and shortcut
    @test OFOND.is_outsource_direct_shortcut(TTGraph, supp1FromDel2, supp1FromDel1)
    @test OFOND.is_outsource_direct_shortcut(TTGraph, supp1FromDel2, xdockFromDel1)
    @test OFOND.is_outsource_direct_shortcut(TTGraph, supp1FromDel2, plantFromDel0)
    @test !OFOND.is_outsource_direct_shortcut(TTGraph, xdockFromDel1, plantFromDel0)
    # outsource and direct 
    @test !OFOND.is_outsource_direct(TTGraph, supp1FromDel2, supp1FromDel1)
    @test OFOND.is_outsource_direct(TTGraph, supp1FromDel2, xdockFromDel1)
    @test OFOND.is_outsource_direct(TTGraph, supp1FromDel2, plantFromDel0)
    @test !OFOND.is_outsource_direct(TTGraph, xdockFromDel1, plantFromDel0)
end

@testset "Complete paths" begin
    @test OFOND.get_shortcut_part(TTGraph, 1, 3) == [4, 3]
    @test OFOND.get_shortcut_part(TTGraph, 1, 2) == [4, 3, 2]
    @test OFOND.get_shortcut_part(TTGraph, 2, 5) == [7, 6, 5]
    @test OFOND.get_shortcut_part(TTGraph, 3, 8) == [11, 10, 9, 8]
end

@testset "Paths to update" begin
    paths = [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    sol = OFOND.Solution(instance)
    OFOND.update_solution!(sol, instance, bundles, paths)
    plantPert = OFOND.get_perturbation(:single_plant, instance, sol)
    @test OFOND.get_lns_paths_to_update(sol, [bundle1], plantPert) ==
        [[supp1FromDel2, xdockFromDel1, plantFromDel0]]
    twoSharePert = OFOND.two_shared_node_perturbation(
        instance, sol, xdockFromDel1, plantFromDel0
    )
    @test OFOND.get_lns_paths_to_update(sol, [bundle1], twoSharePert) ==
        [[xdockFromDel1, plantFromDel0]]
    attractPert = OFOND.get_perturbation(:attract_reduce, instance, sol)
    @test OFOND.get_lns_paths_to_update(sol, [bundle2, bundle3], attractPert) ==
        [[supp2FromDel1, plantFromDel0], [supp3FromDel2, plantFromDel0]]
end

@testset "Model with optimizer" begin
    model = OFOND.model_with_optimizer()
    @test solver_name(model) == "HiGHS"
    @test get_attribute(model, "mip_rel_gap") ≈ 0.02
    @test get_attribute(model, MOI.Silent())
    @test get_attribute(model, MOI.TimeLimitSec()) ≈ 150.0

    model = OFOND.model_with_optimizer(; MIPGap=0.1, timeLimit=60.0, verbose=true)
    @test solver_name(model) == "HiGHS"
    @test get_attribute(model, "mip_rel_gap") ≈ 0.1
    @test !get_attribute(model, MOI.Silent())
    @test get_attribute(model, MOI.TimeLimitSec()) ≈ 60.0
end

@testset "Perturbate filtering" begin
    paths = [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    sol = OFOND.Solution(instance)
    OFOND.update_solution!(sol, instance, bundles, paths)
    # Is perturbation empty ?
    pert = OFOND.arc_flow_perturbation(instance, sol, Int[])
    @test OFOND.is_perturbation_empty(pert)
    pert = OFOND.arc_flow_perturbation(instance, sol, [1, 2, 3])
    @test !OFOND.is_perturbation_empty(pert)
    # Are paths new ?
    oldPaths = [[1, 2], [3, 4]]
    @test !OFOND.are_new_paths(oldPaths, [[1, 2], [3, 4]])
    @test OFOND.are_new_paths(oldPaths, [[1, 2], [3, 5]])
    @test OFOND.are_new_paths(oldPaths, [[1, 3], [3, 4]])
    # Which bundle path changed ?
    oldPaths = [[1, 2], [3, 4], [3, 4]]
    pert = OFOND.Perturbation(:arc_flow, [2, 1, 3], oldPaths, spzeros(Int, (3, 3)))
    @test OFOND.get_new_paths_idx(pert, oldPaths, [[1, 2], [2, 4], [3, 4]]) == [2]
    @test OFOND.get_new_paths_idx(pert, oldPaths, [[1, 3], [3, 4], [5, 4]]) == [1, 3]
end

@testset "Save previous bins shortcut" begin
    paths = [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    sol = OFOND.Solution(instance)
    OFOND.update_solution!(sol, instance, bundles, paths)
    TSPath = [supp1Step2, xdockStep3, portStep4, plantStep1]
    workingArcs = sparse(
        [supp1Step2, xdockStep3, portStep4],
        [xdockStep3, portStep4, plantStep1],
        [true, true, true],
        nv(TSGraph.graph),
        nv(TSGraph.graph),
    )
    OFOND.add_order!(sol, TSGraph, TSPath, order1)
    previousBins = OFOND.save_previous_bins(sol, workingArcs)
    I, J, V = findnz(previousBins)
    @test I == [supp1Step2, xdockStep3, portStep4]
    @test J == [xdockStep3, portStep4, plantStep1]
    @test V == fill([OFOND.Bin(30, 20, [commodity1, commodity1])], 3)
end