# Define supplier, platform, and plant
supplier1 = OFOND.NetworkNode("001", :supplier, "Supp1", LLA(1, 0), "FR", "EU", false, 0.0)
supplier2 = OFOND.NetworkNode("002", :supplier, "Supp2", LLA(0, 1), "FR", "EU", false, 0.0)
xdock = OFOND.NetworkNode("004", :xdock, "XDock1", LLA(2, 1), "FR", "EU", true, 1.0)
port_l = OFOND.NetworkNode("005", :port_l, "PortL1", LLA(3, 3), "FR", "EU", true, 0.0)
plant = OFOND.NetworkNode("003", :plant, "Plant1", LLA(4, 4), "FR", "EU", false, 0.0)

# Define arcs between the nodes
supp1_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 50)
supp2_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 50)
supp1_to_plant = OFOND.NetworkArc(:direct, 2.0, 2, false, 10.0, false, 1.0, 50)
supp2_to_plant = OFOND.NetworkArc(:direct, 2.0, 1, false, 10.0, false, 1.0, 50)
plat_to_plant = OFOND.NetworkArc(:delivery, 1.0, 1, true, 4.0, false, 1.0, 50)
xdock_to_port = OFOND.NetworkArc(:cross_plat, 1.0, 1, true, 4.0, false, 0.0, 50)
port_to_plant = OFOND.NetworkArc(:oversea, 1.0, 1, true, 4.0, false, 1.0, 50)

# Add them all to the network
network = OFOND.NetworkGraph()
OFOND.add_node!(network, supplier1)
OFOND.add_node!(network, supplier2)
OFOND.add_node!(network, xdock)
OFOND.add_node!(network, port_l)
OFOND.add_node!(network, plant)
OFOND.add_arc!(network, xdock, plant, plat_to_plant)
OFOND.add_arc!(network, supplier1, xdock, supp1_to_plat)
OFOND.add_arc!(network, supplier2, xdock, supp2_to_plat)
OFOND.add_arc!(network, supplier1, plant, supp1_to_plant)
OFOND.add_arc!(network, supplier2, plant, supp2_to_plant)
OFOND.add_arc!(network, xdock, port_l, xdock_to_port)
OFOND.add_arc!(network, port_l, plant, port_to_plant)

# Define bundles
commodity1 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("B123", 10, 2.5))
order1 = OFOND.Order(hash("C123"), 1, [commodity1, commodity1])
bundle1 = OFOND.Bundle(supplier1, plant, [order1], 1, hash(supplier1, hash(plant)), 10, 2)

commodity2 = OFOND.Commodity(1, hash("B456"), OFOND.CommodityData("C456", 15, 3.5))
order2 = OFOND.Order(hash("D456"), 1, [commodity2, commodity2])
bundle2 = OFOND.Bundle(supplier2, plant, [order2], 2, hash(supplier2, hash(plant)), 15, 1)

order3 = OFOND.Order(hash("E789"), 1, [commodity1, commodity2])
bundle3 = OFOND.Bundle(supplier1, plant, [order3], 3, hash(supplier1, hash(plant)), 10, 3)

bundles = [bundle1, bundle2, bundle3]

# Test constructor for TimeSpaceGraph structure
@testset "Base Constructors" begin
    tsg = OFOND.TimeSpaceGraph()
    @test nv(tsg.graph) == 0
    @test isempty(tsg.networkNodes)
    @test isempty(tsg.timeStep)
    @test tsg.timeHorizon == 0

    tsg = OFOND.TimeSpaceGraph(10)
    @test nv(tsg.graph) == 0
    @test tsg.timeHorizon == 10

    I = [1, 2, 1]
    J = [3, 3, 2]
    arcs = [supp1_to_plant, plat_to_plant, supp1_to_plat]
    costs = [11.0, 4.0, 5.0]
    tsg = OFOND.TimeSpaceGraph(tsg, I, J, arcs, costs)
    @test nv(tsg.graph) == 0
    @test tsg.currentCost[1, 3] ≈ 11.0
    @test tsg.networkArcs[1, 3] === supp1_to_plant
end

# Test constructor sub-functions

tsg = OFOND.TimeSpaceGraph(4)
@testset "Add network node" begin
    OFOND.add_network_node!(tsg, supplier1)
    @test nv(tsg.graph) == 4
    @test all(n -> n === supplier1, tsg.networkNodes)
    @test tsg.timeStep == [1, 2, 3, 4]
    @test [tsg.hashToIdx[hash(i, supplier1.hash)] for i in 1:4] == [1, 2, 3, 4]

    OFOND.add_network_node!(tsg, plant)
    @test nv(tsg.graph) == 8
    @test all(n -> n === plant, tsg.networkNodes[5:8])
    @test tsg.timeStep[5:8] == [1, 2, 3, 4]
    @test [tsg.hashToIdx[hash(i, plant.hash)] for i in 1:4] == [5, 6, 7, 8]
end

@testset "Add network arc" begin
    srcs, dsts = OFOND.add_network_arc!(tsg, supplier1, plant, supp1_to_plant)
    @test ne(tsg.graph) == 4
    @test has_edge(tsg.graph, 1, 7)
    @test has_edge(tsg.graph, 2, 8)
    @test has_edge(tsg.graph, 3, 5)
    @test has_edge(tsg.graph, 4, 6)
    @test srcs == [1, 2, 3, 4]
    @test dsts == [7, 8, 5, 6]

    I, J, arcs, costs = Int[], Int[], OFOND.NetworkArc[], Float64[]
    OFOND.add_arc_to_vectors!((I, J, arcs, costs), srcs, dsts, supp1_to_plant)
    @test I == [1, 2, 3, 4]
    @test J == [7, 8, 5, 6]
    @test arcs == [supp1_to_plant, supp1_to_plant, supp1_to_plant, supp1_to_plant]
    @test arcs[1] === supp1_to_plant
    @test costs == fill(OFOND.EPS, 4)
end

# Test complete constructor

tsg = OFOND.TimeSpaceGraph(network, 4)
allNodes = vcat(
    fill(supplier1, 4), fill(supplier2, 4), fill(xdock, 4), fill(port_l, 4), fill(plant, 4)
)
allSteps = repeat([1, 2, 3, 4], 5)
allIdxs = [tsg.hashToIdx[hash(step, node.hash)] for (step, node) in zip(allSteps, allNodes)]
@testset "Complete constructor" begin
    # Nodes : 4 of each
    @test nv(tsg.graph) == 20
    @test tsg.networkNodes == allNodes
    @test tsg.timeStep == allSteps
    # Arcs : 4 times each
    @test ne(tsg.graph) == 28
    @test length(tsg.commonArcs) == 12
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
    V = vcat(
        fill(supp1_to_plat, 4),
        fill(supp1_to_plant, 4),
        fill(supp2_to_plat, 4),
        fill(supp2_to_plant, 4),
        fill(xdock_to_port, 4),
        fill(plat_to_plant, 4),
        fill(port_to_plant, 4),
    )
    @test [tsg.networkArcs[i, j] for (i, j) in zip(I, J)] == V
end

@testset "is_path_elementary" begin
    @test OFOND.is_path_elementary(tsg, allIdxs[[1, 10, 15, 19]])
    @test !OFOND.is_path_elementary(tsg, allIdxs[[1, 2, 10, 15, 19]])
end