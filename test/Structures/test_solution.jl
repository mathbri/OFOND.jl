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

# Defining instance
dates = ["2024-01-01", "2024-01-02", "2024-01-03", "2024-01-04"]
partNumbers = Dict(hash("A123") => "A123", hash("B456") => "B456")
instance = OFOND.Instance(network, TTGraph, TSGraph, bundles, 4, dates, partNumbers)

@testset "Constructors" begin
    # COnstrcution with lists
    sol = OFOND.Solution(
        [[1], [2, 3]],
        Dict(1 => [1], 2 => [2, 3]),
        sparse([1, 2, 3], [2, 3, 1], [OFOND.Bin[], OFOND.Bin[], OFOND.Bin[]]),
    )
    @test sol.bundlePaths == [[1], [2, 3]]
    @test sol.bundlesOnNode == Dict(1 => [1], 2 => [2, 3])
    @test sol.bins == sparse([1, 2, 3], [2, 3, 1], [OFOND.Bin[], OFOND.Bin[], OFOND.Bin[]])
    # COnstrcution with graphs and bundles
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    @test sol.bundlePaths == [[-1, -1], [-1, -1], [-1, -1]]
    @test sol.bundlesOnNode == Dict{Int,Vector{Int}}(zip(common, [Int[] for _ in common]))
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
    V = fill(OFOND.Bin[], length(I))
    @test [sol.bins[i, j] for (i, j) in zip(I, J)] == V
    # Constrcution with instance
    sol2 = OFOND.Solution(instance)
    @test sol2.bundlePaths == sol.bundlePaths
    @test sol2.bundlesOnNode == sol.bundlesOnNode
    @test sol2.bins == sol.bins
end

supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
TTPath = [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]

@testset "Update bundle path" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # Adding TTPath for bundle 1
    oldPart = OFOND.update_bundle_path!(sol, bundle1, TTPath; partial=false)
    @test oldPart == [-1, -1]
    @test sol.bundlePaths[1] == TTPath
    @test sol.bundlePaths[2:3] == [[-1, -1], [-1, -1]]
    # Adding a partial part of the TTPath for bundle 1
    oldPart = OFOND.update_bundle_path!(
        sol, bundle1, [xdockFromDel2, xdockFromDel2, portFromDel1]; partial=true
    )
    @test oldPart == [xdockFromDel2, portFromDel1]
    @test sol.bundlePaths[1] ==
        [supp1FromDel3, xdockFromDel2, xdockFromDel2, portFromDel1, plantFromDel0]
    @test sol.bundlePaths[2:3] == [[-1, -1], [-1, -1]]
    # Doing the same with another part
    oldPart = OFOND.update_bundle_path!(
        sol, bundle1, [xdockFromDel2, 20, portFromDel1]; partial=true
    )
    @test oldPart == [xdockFromDel2, xdockFromDel2, portFromDel1]
    @test sol.bundlePaths[1] ==
        [supp1FromDel3, xdockFromDel2, 20, portFromDel1, plantFromDel0]
    @test sol.bundlePaths[2:3] == [[-1, -1], [-1, -1]]
end

@testset "Update bundle on nodes" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # Adding bundle 1 on nodes of the TTPath
    value = OFOND.update_bundle_on_nodes!(sol, bundle1, TTPath; partial=false)
    @test value === nothing
    @test sol.bundlePaths == [[-1, -1], [-1, -1], [-1, -1]]
    @test_throws KeyError sol.bundlesOnNode[supp1FromDel3]
    @test sol.bundlesOnNode[xdockFromDel2] == [1]
    @test sol.bundlesOnNode[portFromDel1] == [1]
    @test sol.bundlesOnNode[plantFromDel0] == [1]
    # Testing for bundle 2 on another path
    OFOND.update_bundle_on_nodes!(
        sol, bundle2, [xdockFromDel2, portFromDel1]; partial=false
    )
    @test sol.bundlesOnNode[xdockFromDel2] == [1, 2]
    @test sol.bundlesOnNode[portFromDel1] == [1, 2]
    # Removing bundle 1 from the nodes of the TTPath
    OFOND.update_bundle_on_nodes!(sol, bundle1, TTPath; partial=false, remove=true)
    @test sol.bundlesOnNode[xdockFromDel2] == [2]
    @test sol.bundlesOnNode[portFromDel1] == [2]
    @test sol.bundlesOnNode[plantFromDel0] == Int[]
    # Adding bundle 1 on a partial part of path 
    OFOND.update_bundle_on_nodes!(sol, bundle1, [20, xdockFromDel2, 21]; partial=true)
    @test sol.bundlesOnNode[xdockFromDel2] == [2, 1]
    @test sol.bundlesOnNode[portFromDel1] == [2]
    @test sol.bundlesOnNode[plantFromDel0] == Int[]
    # Mimicking the fact that after remocing a partial part, a node in the old part is there in the rest of the path 
    OFOND.update_bundle_path!(sol, bundle1, [xdockFromDel2, plantFromDel0]; partial=false)
    push!(sol.bundlesOnNode[portFromDel1], 1)
    push!(sol.bundlesOnNode[xdockFromDel2], 1)
    OFOND.update_bundle_on_nodes!(
        sol, bundle1, [20, xdockFromDel2, portFromDel1, 21]; partial=true, remove=true
    )
    @test sol.bundlesOnNode[xdockFromDel2] == [2, 1, 1] # not removed here because still in the path
    @test sol.bundlesOnNode[portFromDel1] == [2] # removed here because not in the path anymore
    @test sol.bundlesOnNode[plantFromDel0] == Int[]
end

@testset "Add / remove paths" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.add_path!(sol, bundle1, TTPath)
    @test sol.bundlePaths[1] == TTPath
    @test sol.bundlePaths[2:3] == [[-1, -1], [-1, -1]]
    @test_throws KeyError sol.bundlesOnNode[supp1FromDel3]
    @test sol.bundlesOnNode[xdockFromDel2] == [1]
    @test sol.bundlesOnNode[portFromDel1] == [1]
    @test sol.bundlesOnNode[plantFromDel0] == [1]

    OFOND.add_path!(
        sol, bundle1, [xdockFromDel2, xdockFromDel2, portFromDel1]; partial=true
    )
    @test sol.bundlePaths[1] ==
        [supp1FromDel3, xdockFromDel2, xdockFromDel2, portFromDel1, plantFromDel0]
    @test sol.bundlesOnNode[xdockFromDel2] == [1, 1]

    OFOND.add_path!(sol, bundle2, [xdockFromDel2, portFromDel1])
    oldPart = OFOND.remove_path!(sol, bundle1; src=xdockFromDel2, dst=portFromDel1)
    @test oldPart == [xdockFromDel2, xdockFromDel2, portFromDel1]
    @test sol.bundlePaths[1] == TTPath
    # Removing the second xdockFromDel2 from the path of bundle 1 doesn't trigger the filtering of idx 1 
    @test sol.bundlesOnNode[xdockFromDel2] == [1, 1, 2]
    @test sol.bundlesOnNode[portFromDel1] == [1, 2]
    @test sol.bundlesOnNode[plantFromDel0] == [1]

    oldPart = OFOND.remove_path!(sol, bundle1)
    @test oldPart == TTPath
    @test sol.bundlePaths[1] == [-1, -1]
    @test sol.bundlesOnNode[xdockFromDel2] == [2]
    @test sol.bundlesOnNode[portFromDel1] == [2]
    @test sol.bundlesOnNode[plantFromDel0] == Int[]
end

@testset "Check path count" begin
    sol = OFOND.Solution(
        [[1], [2, 3]],
        Dict(1 => [1], 2 => [2, 3]),
        sparse([1, 2, 3], [2, 3, 1], [OFOND.Bin[], OFOND.Bin[], OFOND.Bin[]]),
    )
    @test !OFOND.check_enough_paths(instance, sol; verbose=false)
    @test_warn "Infeasible solution : 3 bundles and 2 paths" OFOND.check_enough_paths(
        instance, sol; verbose=true
    )

    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    @test OFOND.check_enough_paths(instance, sol; verbose=false)
    @test OFOND.check_enough_paths(instance, sol; verbose=true)
end

sol = OFOND.Solution(TTGraph, TSGraph, bundles)

@testset "Check supplier / customer" begin
    @test !OFOND.check_supplier(instance, bundle1, 15; verbose=false)
    @test_warn "Infeasible solution" OFOND.check_supplier(
        instance, bundle1, 15; verbose=true
    )
    @test !OFOND.check_customer(instance, bundle1, 1; verbose=false)
    @test_warn "Infeasible solution" OFOND.check_customer(
        instance, bundle1, 1; verbose=true
    )

    OFOND.add_path!(sol, bundle1, TTPath)
    @test OFOND.check_supplier(instance, bundle1, supp1FromDel3; verbose=false)
    @test OFOND.check_supplier(instance, bundle1, supp1FromDel3; verbose=true)
    @test OFOND.check_customer(instance, bundle1, plantFromDel0; verbose=false)
    @test OFOND.check_customer(instance, bundle1, plantFromDel0; verbose=true)
    @test !OFOND.check_supplier(instance, bundle2, supp1FromDel3; verbose=false)
end

@testset "Check path continuity" begin
    @test !OFOND.check_path_continuity(
        instance, [supp1FromDel3, plantFromDel0]; verbose=false
    )
    @test_warn "Infeasible solution" OFOND.check_path_continuity(
        instance, [supp1FromDel3, plantFromDel0]; verbose=true
    )
    @test OFOND.check_path_continuity(instance, TTPath; verbose=false)
end

supp1step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]
supp2fromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
supp1step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
supp2step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
supp1Step4 = TSGraph.hashToIdx[hash(4, supplier1.hash)]

@testset "Asked and Routed quantity helpers" begin
    # creators 
    asked, routed = OFOND.create_asked_routed_quantities(instance)
    @test asked == Dict(hash(t, plant.hash) => Dict{UInt,Int}() for t in 1:4)
    @test routed == Dict(hash(t, plant.hash) => Dict{UInt,Int}() for t in 1:4)
    # updaters
    OFOND.update_asked_quantities!(asked, bundle1)
    @test asked == Dict(
        hash(1, plant.hash) => Dict(hash("A123") => 2),
        hash(2, plant.hash) => Dict{UInt,Int}(),
        hash(3, plant.hash) => Dict{UInt,Int}(),
        hash(4, plant.hash) => Dict{UInt,Int}(),
    )
    push!(sol.bins[supp1step2, xdockStep3], OFOND.Bin(30, 20, [commodity1, commodity1]))
    push!(sol.bins[xdockStep3, portStep4], OFOND.Bin(30, 20, [commodity1, commodity1]))
    push!(sol.bins[portStep4, plantStep1], OFOND.Bin(30, 20, [commodity1, commodity1]))
    OFOND.update_routed_quantities!(routed, instance, sol)
    @test routed == Dict(
        hash(1, plant.hash) => Dict(hash("A123") => 2),
        hash(2, plant.hash) => Dict{UInt,Int}(),
        hash(3, plant.hash) => Dict{UInt,Int}(),
        hash(4, plant.hash) => Dict{UInt,Int}(),
    )
    plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]
    push!(sol.bins[supp1Step4, plantStep2], OFOND.Bin(30, 20, [commodity1, commodity2]))
    OFOND.update_routed_quantities!(routed, instance, sol)
    @test routed == Dict(
        hash(1, plant.hash) => Dict(hash("A123") => 4),
        hash(2, plant.hash) => Dict(hash("A123") => 1, hash("B456") => 1),
        hash(3, plant.hash) => Dict{UInt,Int}(),
        hash(4, plant.hash) => Dict{UInt,Int}(),
    )
end

OFOND.add_path!(sol, bundle1, TTPath)
@testset "Check quantities" begin
    # empty
    asked, routed = OFOND.create_asked_routed_quantities(instance)
    @test OFOND.check_quantities(instance, asked, routed; verbose=false)
    @test OFOND.check_quantities(instance, asked, routed; verbose=true)
    # not empty
    asked = Dict(
        hash(1, plant.hash) => Dict(hash("A123") => 2),
        hash(2, plant.hash) => Dict{UInt,Int}(),
        hash(3, plant.hash) => Dict{UInt,Int}(),
        hash(4, plant.hash) => Dict{UInt,Int}(),
    )
    routed = Dict(
        hash(1, plant.hash) => Dict(hash("A123") => 2),
        hash(2, plant.hash) => Dict{UInt,Int}(),
        hash(3, plant.hash) => Dict{UInt,Int}(),
        hash(4, plant.hash) => Dict{UInt,Int}(),
    )
    @test OFOND.check_quantities(instance, asked, routed; verbose=false)
    @test OFOND.check_quantities(instance, asked, routed; verbose=true)
    routed = Dict(
        hash(1, plant.hash) => Dict(hash("A123") => 5, hash("B456") => 1),
        hash(2, plant.hash) => Dict(hash("A123") => 1, hash("B456") => 1),
        hash(3, plant.hash) => Dict{UInt,Int}(),
        hash(4, plant.hash) => Dict{UInt,Int}(),
    )
    @test !OFOND.check_quantities(instance, asked, routed; verbose=false)
    # TODO : capturing prints can be done with sprint(f, ...)
    same = @test_warn "Infeasible solution" OFOND.check_quantities(
        instance, asked, routed; verbose=true
    )
    @test !same
end

sol = OFOND.Solution(TTGraph, TSGraph, bundles)

OFOND.add_path!(sol, bundle1, TTPath)
OFOND.add_path!(sol, bundle2, [1, 1])
OFOND.add_path!(sol, bundle3, [1, 1])

supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]
supp3step3 = TSGraph.hashToIdx[hash(3, supplier3.hash)]
supp3step4 = TSGraph.hashToIdx[hash(4, supplier3.hash)]
plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]

@testset "is_feasible" begin
    # check that is_feasible returns false
    @test !OFOND.is_feasible(instance, sol)
    @test_warn "Infeasible solution" OFOND.is_feasible(instance, sol; verbose=true)
    # add direct paths for the other bundles
    OFOND.add_path!(sol, bundle2, [supp2fromDel1, plantFromDel0])
    OFOND.add_path!(sol, bundle3, [supp3FromDel2, plantFromDel0])
    # add commodities on direct arc for bundle 2 and 3
    supp2Step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
    push!(sol.bins[supp2Step4, plantStep1], OFOND.Bin(25, 25, [commodity2, commodity2]))
    push!(
        sol.bins[supp3step3, plantStep1],
        OFOND.Bin(5, 45, [commodity2, commodity1, commodity1, commodity1]),
    )
    push!(sol.bins[supp3step4, plantStep2], OFOND.Bin(25, 25, [commodity2, commodity1]))
    # check that is_feasible returns true
    @test OFOND.is_feasible(instance, sol)
    @test OFOND.is_feasible(instance, sol; verbose=true)
end

commodity3 = OFOND.Commodity(1, hash("B456"), 5, 4.5)

@testset "Cost computation" begin
    bins = [OFOND.Bin(50)]
    for com in [commodity1, commodity2, commodity3]
        OFOND.add!(bins[1], com)
    end
    # volume = 30/VOLUME_FACTOR, carbonCost = 1, unitCost = 10, stockCost = 10.5, distance = 2
    @test OFOND.compute_arc_cost(
        TSGraph, bins, supp2step4, plantStep1; current_cost=false
    ) ≈ 30 / 51 * 1 + 10 + 10.5 * 2
    # volume = 30, stockCost = 10.5, distance = 1, unitCost = 4, carbonCost = 1
    @test OFOND.compute_arc_cost(TSGraph, bins, portStep4, plantStep1; current_cost=false) ≈
        15.1
    # volume = 30, stockCost = 10.5, distance = 1, unitCost = 4, carbonCost = 0, nodeCost = 1, linear
    # 10.5 + 3/5 * 4 + 30/100*1 = 13.2
    xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]
    @test OFOND.compute_arc_cost(
        TSGraph, bins, supp2step4, xdockStep1; current_cost=false
    ) ≈ 1 * 30 / 100 + 30 / 51 * 4 + 1 * 10.5
    # test on the whole solution
    @test OFOND.compute_cost(instance, sol; current_cost=false) ≈ 79.83634992458522
    @test OFOND.compute_cost(instance, sol) ≈ 79.83634992458522
end

# Removing bundle 2 form the sub instance
subBundles = [bundle11, OFOND.change_idx(bundle33, 2)]
# Defining corresponding sub network
subNetwork = deepcopy(network)
rem_vertex!(subNetwork.graph, code_for(network.graph, supplier2.hash))
# Defining corresponding sub instance
subInstance = OFOND.Instance(
    subNetwork,
    OFOND.TravelTimeGraph(subNetwork, subBundles),
    OFOND.TimeSpaceGraph(subNetwork, 4),
    subBundles,
    4,
    dates,
    partNumbers,
)

xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]
supp2fromDel0 = TTGraph.hashToIdx[hash(0, supplier2.hash)]
supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]

subSupp1FromDel3 = subInstance.travelTimeGraph.hashToIdx[hash(3, supplier1.hash)]
subSupp1FromDel2 = subInstance.travelTimeGraph.hashToIdx[hash(2, supplier1.hash)]

subSupp3FromDel2 = subInstance.travelTimeGraph.hashToIdx[hash(2, supplier3.hash)]

subPortFromDel1 = subInstance.travelTimeGraph.hashToIdx[hash(1, port_l.hash)]
subXdockFromDel2 = subInstance.travelTimeGraph.hashToIdx[hash(2, xdock.hash)]
subXdockFromDel1 = subInstance.travelTimeGraph.hashToIdx[hash(1, xdock.hash)]

subPlantFromDel0 = subInstance.travelTimeGraph.hashToIdx[hash(0, plant.hash)]

subTTPath = [subSupp1FromDel3, subXdockFromDel2, subPortFromDel1, subPlantFromDel0]

subSupp1Step2 = subInstance.timeSpaceGraph.hashToIdx[hash(2, supplier1.hash)]
subXdockStep3 = subInstance.timeSpaceGraph.hashToIdx[hash(3, xdock.hash)]
subPortStep4 = subInstance.timeSpaceGraph.hashToIdx[hash(4, port_l.hash)]
subPlantStep1 = subInstance.timeSpaceGraph.hashToIdx[hash(1, plant.hash)]

subSupp3step3 = subInstance.timeSpaceGraph.hashToIdx[hash(3, supplier3.hash)]

@testset "project / repair paths" begin
    # project paths	
    @test OFOND.project_on_sub_instance(
        [supp1FromDel2, xdockFromDel1, plantFromDel0], instance, subInstance
    ) == [subSupp1FromDel2, subXdockFromDel1, subPlantFromDel0]
    # projecting with a node that doesn't exist anymore
    @test OFOND.project_on_sub_instance(
        [supp1FromDel2, supp2fromDel0], instance, subInstance
    ) == Int[]
    # repair paths
    allPaths = [[supp1FromDel2, xdockFromDel1, plantFromDel0], Int[]]
    OFOND.repair_paths!(allPaths, instance)
    @test allPaths ==
        [[supp1FromDel2, xdockFromDel1, plantFromDel0], [supp2FromDel1, plantFromDel0]]
end

# adding commodities to be filtered
push!(sol.bins[supp1step3, plantStep1], OFOND.Bin(20, 30, [commodity2, commodity2]))
# extracting sub solution
subSol = OFOND.extract_sub_solution(sol, instance, subInstance)

@testset "Extract sub solution" begin
    @test subSol.bundlePaths == [subTTPath, [subSupp3FromDel2, subPlantFromDel0]]
    @test subSol.bins != sol.bins
    @test subSol.bins[subSupp1Step2, subXdockStep3] ==
        [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test subSol.bins[subPortStep4, subPlantStep1] ==
        [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test subSol.bins[subSupp3step3, subPlantStep1] ==
        [OFOND.Bin(27, 25, [commodity2, commodity1])]
end

@testset "Extract filtered instance" begin
    subInstance2 = OFOND.extract_filtered_instance(subInstance, subSol)
    # Only the bundle 1 stays because he is not on a direct path
    @test subInstance2.bundles == [bundle11]
    @test nv(subInstance2.networkGraph.graph) == 4
    @test ne(subInstance2.networkGraph.graph) == 6
end

@testset "Fuse solutions" begin
    fusedSol = OFOND.fuse_solutions(subSol, sol, instance, subInstance)
    @test fusedSol.bundlePaths ==
        [sol.bundlePaths[1], sol.bundlePaths[2], sol.bundlePaths[3]]
    @test fusedSol.bins != sol.bins
    # @test fusedSol.bins[supp1step2, xdockStep3] ==
    #     [OFOND.Bin(5, 45, [commodity1, commodity1, commodity2, commodity1])]
    # @test fusedSol.bins[portStep4, plantStep1] ==
    #     [OFOND.Bin(5, 45, [commodity1, commodity1, commodity2, commodity1])]
    # @test fusedSol.bins[supp2step4, plantStep1] ==
    #     OFOND.Bin[OFOND.Bin(20, 30, [commodity2, commodity2])]
    # @test fusedSol.bins[supp1step3, plantStep1] == OFOND.Bin[]
end

@testset "Solution deepcopy" begin
    sol2 = deepcopy(sol)
    @test sol2.bundlePaths == sol.bundlePaths
    @test sol2.bundlesOnNode == sol.bundlesOnNode
    @test sol2.bins == sol.bins
end