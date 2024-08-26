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
    @testset "empty load content" for (src, dst) in TSGraph.commonArcs
        if src == xdockStep3 && dst == portStep4
            @test relaxedSol.loads[src, dst] == 60
        elseif src == portStep4 && dst == plantStep1
            @test relaxedSol.loads[src, dst] == 5
        else
            @test relaxedSol.loads[src, dst] == 0
        end
    end
end