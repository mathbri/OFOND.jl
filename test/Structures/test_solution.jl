# Define supplier, platform, and plant
supplier1 = OFOND.NetworkNode("001", :supplier, "FR", "EU", false, 0.0)
supplier2 = OFOND.NetworkNode("002", :supplier, "FR", "EU", false, 0.0)
xdock = OFOND.NetworkNode("004", :xdock, "FR", "EU", true, 1.0)
port_l = OFOND.NetworkNode("005", :pol, "FR", "EU", true, 0.0)
plant = OFOND.NetworkNode("003", :plant, "FR", "EU", false, 0.0)

# Define arcs between the nodes
supp_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 50)
supp1_to_plant = OFOND.NetworkArc(:direct, 2.0, 2, false, 10.0, false, 1.0, 50)
supp2_to_plant = OFOND.NetworkArc(:direct, 2.0, 1, false, 10.0, false, 1.0, 50)
plat_to_plant = OFOND.NetworkArc(:delivery, 1.0, 1, true, 4.0, false, 1.0, 50)
xdock_to_port = OFOND.NetworkArc(:cross_plat, 1.0, 1, true, 4.0, false, 0.0, 50)
port_to_plant = OFOND.NetworkArc(:oversea, 1.0, 1, true, 4.0, false, 1.0, 50)

# Add them all to the network
network = OFOND.NetworkGraph()
for node in [supplier1, supplier2, xdock, port_l, plant]
    OFOND.add_node!(network, node)
end
OFOND.add_arc!(network, xdock, plant, plat_to_plant)
OFOND.add_arc!(network, supplier1, xdock, supp_to_plat)
OFOND.add_arc!(network, supplier2, xdock, supp_to_plat)
OFOND.add_arc!(network, supplier1, plant, supp1_to_plant)
OFOND.add_arc!(network, supplier2, plant, supp2_to_plant)
OFOND.add_arc!(network, xdock, port_l, xdock_to_port)
OFOND.add_arc!(network, port_l, plant, port_to_plant)

# Define bundles
bpDict = Dict(
    :direct => 2, :cross_plat => 2, :delivery => 2, :oversea => 2, :port_transport => 2
)
commodity1 = OFOND.Commodity(0, hash("A123"), 10, 2.5)
bunH1 = hash(supplier1, hash(plant))
order1 = OFOND.Order(
    bunH1, 1, [commodity1, commodity1], hash(1, bunH1), 20, bpDict, 10, 5.0
)
bundle1 = OFOND.Bundle(supplier1, plant, [order1], 1, bunH1, 10, 2)

commodity2 = OFOND.Commodity(1, hash("B456"), 15, 3.5)
bunH2 = hash(supplier2, hash(plant))
order2 = OFOND.Order(
    bunH2, 1, [commodity2, commodity2], hash(1, bunH2), 30, bpDict, 15, 7.0
)
bundle2 = OFOND.Bundle(supplier2, plant, [order2], 2, bunH2, 15, 1)

order3 = OFOND.Order(
    bunH1, 1, [commodity2, commodity1], hash(1, bunH1), 25, bpDict, 10, 6.0
)
order4 = OFOND.Order(bunH1, 2, [commodity1, commodity2])
bundle3 = OFOND.Bundle(supplier1, plant, [order3], 3, bunH1, 10, 3)

commodity3 = OFOND.Commodity(2, hash("C789"), 5, 4.5)

bundles = [bundle1, bundle2, bundle3]

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

@testset "Constructors" begin
    sol = OFOND.Solution(
        [[1], [2, 3]],
        Dict(1 => [1], 2 => [2, 3]),
        sparse([1, 2, 3], [2, 3, 1], [OFOND.Bin[], OFOND.Bin[], OFOND.Bin[]]),
    )
    @test sol.bundlePaths == [[1], [2, 3]]
    @test sol.bundlesOnNode == Dict(1 => [1], 2 => [2, 3])
    @test sol.bins == sparse([1, 2, 3], [2, 3, 1], [OFOND.Bin[], OFOND.Bin[], OFOND.Bin[]])

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
end

supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
TTPath = [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]

@testset "Update bundle path" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    oldPart = OFOND.update_bundle_path!(sol, bundle1, TTPath; partial=false)
    @test oldPart == [-1, -1]
    @test sol.bundlePaths[1] == TTPath
    @test sol.bundlePaths[2:3] == [[-1, -1], [-1, -1]]

    oldPart = OFOND.update_bundle_path!(
        sol, bundle1, [xdockFromDel2, xdockFromDel2, portFromDel1]; partial=true
    )
    @test oldPart == [xdockFromDel2, portFromDel1]
    @test sol.bundlePaths[1] ==
        [supp1FromDel3, xdockFromDel2, xdockFromDel2, portFromDel1, plantFromDel0]
    @test sol.bundlePaths[2:3] == [[-1, -1], [-1, -1]]

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
    value = OFOND.update_bundle_on_nodes!(sol, bundle1, TTPath; partial=false)
    @test value === nothing
    @test sol.bundlePaths == [[-1, -1], [-1, -1], [-1, -1]]
    @test_throws KeyError sol.bundlesOnNode[supp1FromDel3]
    @test sol.bundlesOnNode[xdockFromDel2] == [1]
    @test sol.bundlesOnNode[portFromDel1] == [1]
    @test sol.bundlesOnNode[plantFromDel0] == [1]

    OFOND.update_bundle_on_nodes!(
        sol, bundle2, [xdockFromDel2, portFromDel1]; partial=false
    )
    @test sol.bundlesOnNode[xdockFromDel2] == [1, 2]
    @test sol.bundlesOnNode[portFromDel1] == [1, 2]

    OFOND.update_bundle_on_nodes!(sol, bundle1, TTPath; partial=false, remove=true)
    @test sol.bundlesOnNode[xdockFromDel2] == [2]
    @test sol.bundlesOnNode[portFromDel1] == [2]
    @test sol.bundlesOnNode[plantFromDel0] == Int[]

    OFOND.update_bundle_on_nodes!(sol, bundle1, [20, xdockFromDel2, 21]; partial=true)
    @test sol.bundlesOnNode[xdockFromDel2] == [2, 1]
    @test sol.bundlesOnNode[portFromDel1] == [2]
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
    @test sol.bundlesOnNode[xdockFromDel2] == [2]
    @test sol.bundlesOnNode[portFromDel1] == [1, 2]
    @test sol.bundlesOnNode[plantFromDel0] == [1]

    oldPart = OFOND.remove_path!(sol, bundle1)
    @test oldPart == TTPath
    @test sol.bundlePaths[1] == [-1, -1]
    @test sol.bundlesOnNode[xdockFromDel2] == [2]
    @test sol.bundlesOnNode[portFromDel1] == [2]
    @test sol.bundlesOnNode[plantFromDel0] == Int[]
end

dates = ["2024-01-01", "2024-01-02", "2024-01-03", "2024-01-04"]
partNumbers = Dict(hash("A123") => "A123", hash("B456") => "B456")
instance = OFOND.Instance(network, TTGraph, TSGraph, bundles, 4, dates, partNumbers)

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
    @test OFOND.check_quantities(asked, routed; verbose=false)
    @test OFOND.check_quantities(asked, routed; verbose=true)
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
    @test OFOND.check_quantities(asked, routed; verbose=false)
    @test OFOND.check_quantities(asked, routed; verbose=true)
    routed = Dict(
        hash(1, plant.hash) => Dict(hash("A123") => 5, hash("B456") => 1),
        hash(2, plant.hash) => Dict(hash("A123") => 1, hash("B456") => 1),
        hash(3, plant.hash) => Dict{UInt,Int}(),
        hash(4, plant.hash) => Dict{UInt,Int}(),
    )
    @test !OFOND.check_quantities(asked, routed; verbose=false)
    same = @test_warn "Infeasible solution" OFOND.check_quantities(
        asked, routed; verbose=true
    )
    @test !same
end

sol = OFOND.Solution(TTGraph, TSGraph, bundles)

OFOND.add_path!(sol, bundle1, TTPath)
OFOND.add_path!(sol, bundle2, [1, 1])
OFOND.add_path!(sol, bundle3, [1, 1])

@testset "is_feasible" begin
    # check that is_feasible returns false
    @test !OFOND.is_feasible(instance, sol)
    @test_warn "Infeasible solution" OFOND.is_feasible(instance, sol; verbose=true)
    # add direct paths for the other bundles
    OFOND.add_path!(sol, bundle2, [supp2fromDel1, plantFromDel0])
    OFOND.add_path!(sol, bundle3, [supp1FromDel2, plantFromDel0])
    # add commodities on direct arc
    push!(
        sol.bins[supp1step3, plantStep1],
        OFOND.Bin(5, 45, [commodity2, commodity1, commodity1, commodity1]),
    )
    supp2Step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
    push!(sol.bins[supp2Step4, plantStep1], OFOND.Bin(25, 25, [commodity2, commodity2]))
    # check that is_feasible returns true
    @test OFOND.is_feasible(instance, sol)
    @test OFOND.is_feasible(instance, sol; verbose=true)
end

@testset "Cost computation" begin
    bins = [OFOND.Bin(50)]
    for com in [commodity1, commodity2, commodity3]
        OFOND.add!(bins[1], com)
    end
    # volume = 30/VOLUME_FACTOR/capacity, stockCost = 10.5, distance = 2, unitCost = 10, carbonCost = 1
    @test OFOND.compute_arc_cost(
        TSGraph, bins, supp2step4, plantStep1; current_cost=false
    ) ≈ 31.006
    # volume = 30, stockCost = 10.5, distance = 1, unitCost = 4, carbonCost = 1
    @test OFOND.compute_arc_cost(TSGraph, bins, portStep4, plantStep1; current_cost=false) ≈
        14.506
    # volume = 30, stockCost = 10.5, distance = 1, unitCost = 4, carbonCost = 0, nodeCost = 1, linear
    # 10.5 + 3/5 * 4 + 30/100*1 = 13.2
    xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]
    @test OFOND.compute_arc_cost(
        TSGraph, bins, supp2step4, xdockStep1; current_cost=false
    ) ≈ 12.906
    # test on the whole solution
    @test OFOND.compute_cost(instance, sol; current_cost=false) ≈ 56.014
    @test OFOND.compute_cost(instance, sol) ≈ 56.014
end

# Re-Define bundles
bunH1 = hash(supplier1, hash(plant))
order1 = OFOND.Order(bunH1, 1, [commodity1, commodity1], 0, 20, bpDict, 10, 5.0)
bundle1 = OFOND.Bundle(supplier1, plant, [order1], 1, bunH1, 10, 2)

bunH2 = hash(supplier2, hash(plant))
order2 = OFOND.Order(bunH2, 1, [commodity2, commodity2], 1, 30, bpDict, 15, 7.0)
bundle2 = OFOND.Bundle(supplier2, plant, [order2], 2, bunH2, 15, 1)

order3 = OFOND.Order(bunH1, 1, [commodity2, commodity1], 0, 25, bpDict, 10, 6.0)
order4 = OFOND.Order(bunH1, 2, [commodity1, commodity2])
bundle3 = OFOND.Bundle(supplier1, plant, [order3], 3, bunH1, 10, 3)

subInstance = OFOND.Instance(
    network,
    deepcopy(TTGraph),
    TSGraph,
    [bundle1, OFOND.change_idx(bundle3, 2)],
    4,
    dates,
    partNumbers,
)
# adding commodities to be filtered
push!(sol.bins[supp1step3, plantStep1], OFOND.Bin(20, 30, [commodity2, commodity2]))
# adding dummy node on instance travel time graph to not have them equal
OFOND.add_network_node!(
    instance.travelTimeGraph, zero(OFOND.NetworkNode), Dict{UInt,Vector{OFOND.Bundle}}(), 2
)

@testset "project / repair paths" begin
    # project paths	
    @test OFOND.project_on_sub_instance(
        [supp1FromDel2, xdockFromDel1, plantFromDel0], instance, subInstance
    ) == [supp1FromDel2, xdockFromDel1, plantFromDel0]
    @test OFOND.project_on_sub_instance([supp1FromDel2, 17], instance, subInstance) == Int[]
    # repair paths
    allPaths = [[supp1FromDel2, xdockFromDel1, plantFromDel0], Int[]]
    OFOND.repair_paths!(allPaths, instance)
    @test allPaths ==
        [[supp1FromDel2, xdockFromDel1, plantFromDel0], [supp2FromDel1, plantFromDel0]]
end

subSol = OFOND.extract_sub_solution(sol, instance, subInstance)
@testset "Extract sub solution" begin
    @test subSol.bundlePaths == sol.bundlePaths[[1, 3]]
    @test subSol.bins != sol.bins
    @test subSol.bins[supp1step2, xdockStep3] ==
        [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test subSol.bins[portStep4, plantStep1] ==
        [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test subSol.bins[supp2step4, plantStep1] == OFOND.Bin[]
    @test subSol.bins[supp1step3, plantStep1] ==
        [OFOND.Bin(25, 25, [commodity2, commodity1])]
end

@testset "Extract filtered instance" begin
    subInstance2 = OFOND.extract_filtered_instance(subInstance, subSol)
    # Only the bundle 1 stays 
    @test subInstance2.bundles == [bundle1]
    @test nv(subInstance2.networkGraph.graph) == 4
    @test ne(subInstance2.networkGraph.graph) == 6
end

@testset "Fuse solutions" begin
    fusedSol = OFOND.fuse_solutions(subSol, sol, instance, subInstance)
    # bundle 1 and 3 are virtually equal, so does the path given in the fusion
    @test fusedSol.bundlePaths ==
        [sol.bundlePaths[1], sol.bundlePaths[2], sol.bundlePaths[1]]
    @test fusedSol.bins != sol.bins
    @test fusedSol.bins[supp1step2, xdockStep3] ==
        [OFOND.Bin(5, 45, [commodity1, commodity1, commodity2, commodity1])]
    @test fusedSol.bins[portStep4, plantStep1] ==
        [OFOND.Bin(5, 45, [commodity1, commodity1, commodity2, commodity1])]
    @test fusedSol.bins[supp2step4, plantStep1] ==
        OFOND.Bin[OFOND.Bin(20, 30, [commodity2, commodity2])]
    @test fusedSol.bins[supp1step3, plantStep1] == OFOND.Bin[]
end