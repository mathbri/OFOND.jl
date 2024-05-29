# Define supplier, platform, and plant
supplier1 = OFOND.NetworkNode("001", :supplier, "Supp1", LLA(1, 0), "FR", "EU", false, 0.0)
supplier2 = OFOND.NetworkNode("002", :supplier, "Supp2", LLA(0, 1), "FR", "EU", false, 0.0)
xdock = OFOND.NetworkNode("004", :xdock, "XDock1", LLA(2, 1), "FR", "EU", true, 1.0)
port_l = OFOND.NetworkNode("005", :port_l, "PortL1", LLA(3, 3), "FR", "EU", true, 0.0)
plant = OFOND.NetworkNode("003", :plant, "Plant1", LLA(4, 4), "FR", "EU", false, 0.0)

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
commodity1 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("B123", 10, 2.5))
bunH1 = hash(supplier1, hash(plant))
order1 = OFOND.Order(
    bunH1, 1, [commodity1, commodity1], hash(1, bunH1), 20, bpDict, 10, 5.0
)
bundle1 = OFOND.Bundle(supplier1, plant, [order1], 1, bunH1, 10, 2)

commodity2 = OFOND.Commodity(1, hash("B456"), OFOND.CommodityData("B456", 15, 3.5))
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

commodity3 = OFOND.Commodity(2, hash("C789"), OFOND.CommodityData("C789", 5, 4.5))

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
        Dict(1 => [bundle1], 2 => [bundle2, bundle3]),
        sparse([1, 2, 3], [2, 3, 1], [OFOND.Bin[], OFOND.Bin[], OFOND.Bin[]]),
    )
    @test sol.bundlePaths == [[1], [2, 3]]
    @test sol.bundlesOnNode == Dict(1 => [bundle1], 2 => [bundle2, bundle3])
    @test sol.bins == sparse([1, 2, 3], [2, 3, 1], [OFOND.Bin[], OFOND.Bin[], OFOND.Bin[]])

    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    @test sol.bundlePaths == [[-1, -1], [-1, -1], [-1, -1]]
    @test sol.bundlesOnNode ==
        Dict{Int,Vector{OFOND.Bundle}}(zip(common, [OFOND.Bundle[] for _ in common]))
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
    @test sol.bundlesOnNode[xdockFromDel2] == [bundle1]
    @test sol.bundlesOnNode[portFromDel1] == [bundle1]
    @test sol.bundlesOnNode[plantFromDel0] == [bundle1]

    OFOND.update_bundle_on_nodes!(
        sol, bundle2, [xdockFromDel2, portFromDel1]; partial=false
    )
    @test sol.bundlesOnNode[xdockFromDel2] == [bundle1, bundle2]
    @test sol.bundlesOnNode[portFromDel1] == [bundle1, bundle2]

    OFOND.update_bundle_on_nodes!(sol, bundle1, TTPath; partial=false, remove=true)
    @test sol.bundlesOnNode[xdockFromDel2] == [bundle2]
    @test sol.bundlesOnNode[portFromDel1] == [bundle2]
    @test sol.bundlesOnNode[plantFromDel0] == OFOND.Bundle[]

    OFOND.update_bundle_on_nodes!(sol, bundle1, [20, xdockFromDel2, 21]; partial=true)
    @test sol.bundlesOnNode[xdockFromDel2] == [bundle2, bundle1]
    @test sol.bundlesOnNode[portFromDel1] == [bundle2]
    @test sol.bundlesOnNode[plantFromDel0] == OFOND.Bundle[]
end

@testset "Add / remove paths" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.add_path!(sol, bundle1, TTPath)
    @test sol.bundlePaths[1] == TTPath
    @test sol.bundlePaths[2:3] == [[-1, -1], [-1, -1]]
    @test_throws KeyError sol.bundlesOnNode[supp1FromDel3]
    @test sol.bundlesOnNode[xdockFromDel2] == [bundle1]
    @test sol.bundlesOnNode[portFromDel1] == [bundle1]
    @test sol.bundlesOnNode[plantFromDel0] == [bundle1]

    OFOND.add_path!(
        sol, bundle1, [xdockFromDel2, xdockFromDel2, portFromDel1]; partial=true
    )
    @test sol.bundlePaths[1] ==
        [supp1FromDel3, xdockFromDel2, xdockFromDel2, portFromDel1, plantFromDel0]
    @test sol.bundlesOnNode[xdockFromDel2] == [bundle1, bundle1]

    OFOND.add_path!(sol, bundle2, [xdockFromDel2, portFromDel1])
    oldPart = OFOND.remove_path!(sol, bundle1; src=xdockFromDel2, dst=portFromDel1)
    @test oldPart == [xdockFromDel2, xdockFromDel2, portFromDel1]
    @test sol.bundlePaths[1] == TTPath
    @test sol.bundlesOnNode[xdockFromDel2] == [bundle2]
    @test sol.bundlesOnNode[portFromDel1] == [bundle1, bundle2]
    @test sol.bundlesOnNode[plantFromDel0] == [bundle1]

    oldPart = OFOND.remove_path!(sol, bundle1)
    @test oldPart == TTPath
    @test sol.bundlePaths[1] == [-1, -1]
    @test sol.bundlesOnNode[xdockFromDel2] == [bundle2]
    @test sol.bundlesOnNode[portFromDel1] == [bundle2]
    @test sol.bundlesOnNode[plantFromDel0] == OFOND.Bundle[]
end

dates = [
    Dates.Date(2020, 1, 1),
    Dates.Date(2020, 1, 2),
    Dates.Date(2020, 1, 3),
    Dates.Date(2020, 1, 4),
]
instance = OFOND.Instance(network, TTGraph, TSGraph, bundles, 4, dates)

@testset "Check path count" begin
    sol = OFOND.Solution(
        [[1], [2, 3]],
        Dict(1 => [bundle1], 2 => [bundle2, bundle3]),
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

OFOND.add_path!(sol, bundle1, TTPath)
@testset "Check quantities" begin
    # add quantities on a arc to test get routed
    xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
    portStep3 = TSGraph.hashToIdx[hash(3, port_l.hash)]
    @test OFOND.get_routed_commodities(sol, order1, xdockStep3, portStep3) ==
        OFOND.Commodity[]
    portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]
    push!(sol.bins[xdockStep3, portStep4], OFOND.Bin(50))
    for com in [commodity1, commodity2, commodity1, commodity3]
        OFOND.add!(sol.bins[xdockStep3, portStep4][1], com)
    end
    @test OFOND.get_routed_commodities(sol, order1, xdockStep3, portStep4) ==
        [commodity1, commodity1]
    @test OFOND.get_routed_commodities(sol, order2, xdockStep3, portStep4) == [commodity2]
    @test OFOND.get_routed_commodities(sol, order3, xdockStep3, portStep4) ==
        [commodity1, commodity1, commodity2]
    # check that checker returns false
    @test !OFOND.check_quantities(
        instance, sol, portFromDel1, plantFromDel0, order1; verbose=false
    )
    @test_warn "Infeasible solution" OFOND.check_quantities(
        instance, sol, portFromDel1, plantFromDel0, order1; verbose=true
    )
    # add the right quantities on the last arc of order1 
    plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]
    push!(sol.bins[portStep4, plantStep1], OFOND.Bin(50))
    for com in [commodity1, commodity1]
        OFOND.add!(sol.bins[portStep4, plantStep1][1], com)
    end
    # check that the checker retrurns true
    @test OFOND.check_quantities(
        instance, sol, portFromDel1, plantFromDel0, order1; verbose=false
    )
    @test OFOND.check_quantities(
        instance, sol, portFromDel1, plantFromDel0, order1; verbose=true
    )
end

supp1step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]
supp2fromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
supp1step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
supp2step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]

@testset "is_feasible" begin
    # check that is_feasible returns false
    @test !OFOND.is_feasible(instance, sol)
    @test_warn "Infeasible solution" OFOND.is_feasible(instance, sol; verbose=true)
    # add commities on first and last arc of TTPath
    push!(sol.bins[supp1step2, xdockStep3], OFOND.Bin(50))
    for com in [commodity1, commodity1]
        OFOND.add!(sol.bins[supp1step2, xdockStep3][1], com)
    end
    # add direct paths for the other bundles
    OFOND.add_path!(sol, bundle2, [supp2fromDel1, plantFromDel0])
    OFOND.add_path!(sol, bundle3, [supp1FromDel2, plantFromDel0])
    # add commodities on direct arc
    push!(sol.bins[supp1step3, plantStep1], OFOND.Bin(50))
    for com in [commodity2, commodity1]
        OFOND.add!(sol.bins[supp1step3, plantStep1][1], com)
    end
    push!(sol.bins[supp2step4, plantStep1], OFOND.Bin(50))
    for com in [commodity2, commodity2]
        arcBins = sol.bins[supp2step4, plantStep1]
        OFOND.add!(arcBins[1], com)
    end
    # check that is_feasible returns true
    @test OFOND.is_feasible(instance, sol)
    @test OFOND.is_feasible(instance, sol; verbose=true)
end

@testset "Cost computation" begin
    bins = [OFOND.Bin(50)]
    for com in [commodity1, commodity2, commodity3]
        OFOND.add!(bins[1], com)
    end
    # volume = 30/VOLUME_FACTOR, stockCost = 10.5, distance = 2, unitCost = 10, carbonCost = 1
    @test OFOND.compute_arc_cost(
        TSGraph, bins, supp2step4, plantStep1; current_cost=false
    ) ≈ 31.3
    # volume = 30, stockCost = 10.5, distance = 1, unitCost = 4, carbonCost = 1
    @test OFOND.compute_arc_cost(TSGraph, bins, portStep4, plantStep1; current_cost=false) ≈
        14.8
    # volume = 30, stockCost = 10.5, distance = 1, unitCost = 4, carbonCost = 0, nodeCost = 1, linear
    # 10.5 + 3/5 * 4 + 30/100*1 = 13.2
    xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]
    @test OFOND.compute_arc_cost(
        TSGraph, bins, supp2step4, xdockStep1; current_cost=false
    ) ≈ 13.2
    # test on the whole solution
    @test OFOND.compute_cost(instance, sol; current_cost=false) ≈ 79.55
end