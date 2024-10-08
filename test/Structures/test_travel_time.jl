# Define supplier, platform, and plant
supplier1 = OFOND.NetworkNode("001", :supplier, "FR", "EU", false, 0.0)
supplier2 = OFOND.NetworkNode("002", :supplier, "FR", "EU", false, 0.0)
xdock = OFOND.NetworkNode("004", :xdock, "FR", "EU", true, 1.0)
port_l = OFOND.NetworkNode("005", :pol, "FR", "EU", true, 0.0)
plant = OFOND.NetworkNode("003", :plant, "FR", "EU", false, 0.0)

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
commodity1 = OFOND.Commodity(0, hash("A123"), 10, 2.5)
order1 = OFOND.Order(hash("C123"), 1, [commodity1, commodity1])
bundle1 = OFOND.Bundle(supplier1, plant, [order1], 1, hash(supplier1, hash(plant)), 10, 2)

commodity2 = OFOND.Commodity(1, hash("B456"), 15, 3.5)
order2 = OFOND.Order(hash("D456"), 1, [commodity2, commodity2])
bundle2 = OFOND.Bundle(supplier2, plant, [order2], 2, hash(supplier2, hash(plant)), 15, 1)

order3 = OFOND.Order(hash("E789"), 1, [commodity1, commodity2])
bundle3 = OFOND.Bundle(supplier1, plant, [order3], 3, hash(supplier1, hash(plant)), 10, 3)

bundles = [bundle1, bundle2, bundle3]

# Test constructor for TravelTimeGraph structure
@testset "Base Constructors" begin
    ttg = OFOND.TravelTimeGraph()
    @test nv(ttg.graph) == 0
    @test isempty(ttg.networkNodes)
    @test isempty(ttg.stepToDel)

    I = [1, 2, 1]
    J = [3, 3, 2]
    arcs = [supp1_to_plant, plat_to_plant, supp1_to_plat]
    costs = [11.0, 4.0, 5.0]
    ttg = OFOND.TravelTimeGraph(ttg, I, J, arcs, costs)
    @test nv(ttg.graph) == 0
    @test ttg.costMatrix[1, 3] ≈ 11.0
    @test ttg.networkArcs[1, 3] === supp1_to_plant

    ttg = OFOND.TravelTimeGraph(bundles)
    @test nv(ttg.graph) == 0
    @test ttg.bundleSrc == ttg.bundleDst == fill(-1, 3)

    # Testing mutability
    @test !ismutable(ttg)
    @test ismutable(ttg.graph)
end

# Test constructor sub-functions

@testset "Bundle on nodes" begin
    # Bundle on nodes test
    @test OFOND.get_bundle_on_nodes(OFOND.Bundle[]) == Dict{UInt,Vector{OFOND.Bundle}}()
    @test OFOND.get_bundle_on_nodes([bundle1]) ==
        Dict(supplier1.hash => [bundle1], plant.hash => [bundle1])
    @test OFOND.get_bundle_on_nodes(bundles) == Dict(
        supplier1.hash => [bundle1, bundle3],
        supplier2.hash => [bundle2],
        plant.hash => [bundle1, bundle2, bundle3],
    )
end

bundleOnNodes = OFOND.get_bundle_on_nodes(bundles)

@testset "Add timed node" begin
    # Add timed node test
    ttg = OFOND.TravelTimeGraph()
    nodeIdx = OFOND.add_timed_node!(ttg, supplier1, 0)
    @test nv(ttg.graph) == 1
    @test ttg.networkNodes[1] === supplier1
    @test ttg.stepToDel[1] == 0
    @test ttg.hashToIdx[hash(0, supplier1.hash)] == 1
    @test nodeIdx == 1

    nodeIdx = OFOND.add_timed_node!(ttg, xdock, 1)
    @test nv(ttg.graph) == 2
    @test ttg.networkNodes[2] === xdock
    @test ttg.stepToDel[2] == 1
    @test ttg.hashToIdx[hash(1, xdock.hash)] == 2
    @test nodeIdx == 2
end

@testset "Add typed node" begin
    ttg = OFOND.TravelTimeGraph(bundles)
    OFOND.add_timed_supplier!(ttg, supplier1, 0, bundleOnNodes)
    @test ttg.hashToIdx[hash(0, supplier1.hash)] == 1
    @test ttg.bundleSrc == fill(-1, 3)

    OFOND.add_timed_supplier!(ttg, supplier1, 2, bundleOnNodes)
    @test ttg.hashToIdx[hash(2, supplier1.hash)] == 2
    @test ttg.bundleSrc == [2, -1, -1]

    OFOND.add_timed_customer!(ttg, plant, bundleOnNodes)
    @test ttg.hashToIdx[hash(0, plant.hash)] == 3
    @test ttg.bundleDst == [3, 3, 3]

    OFOND.add_timed_platform!(ttg, xdock, 0)
    @test ttg.hashToIdx[hash(0, xdock.hash)] == 4
    @test ttg.commonNodes == [4]
end

ttg = OFOND.TravelTimeGraph(bundles)
@testset "Add network node" begin
    OFOND.add_network_node!(ttg, supplier1, bundleOnNodes, 4)
    @test nv(ttg.graph) == 4
    @test all(n -> n === supplier1, ttg.networkNodes)
    @test ttg.stepToDel == [0, 1, 2, 3]
    @test ttg.bundleSrc == [3, -1, 4]
    @test [ttg.hashToIdx[hash(i, supplier1.hash)] for i in 0:3] == [1, 2, 3, 4]

    OFOND.add_network_node!(ttg, plant, bundleOnNodes, 4)
    @test nv(ttg.graph) == 5
    @test ttg.networkNodes[5] === plant
    @test ttg.stepToDel[5] == 0
    @test ttg.hashToIdx[hash(0, plant.hash)] == 5
    @test ttg.bundleDst == [5, 5, 5]

    OFOND.add_network_node!(ttg, xdock, bundleOnNodes, 4)
    @test nv(ttg.graph) == 10
    @test all(n -> n === xdock, ttg.networkNodes[6:end])
    @test ttg.stepToDel[6:end] == [0, 1, 2, 3, 4]
    @test ttg.commonNodes == [6, 7, 8, 9, 10]
end

@testset "Add network arc" begin
    srcs, dsts = OFOND.add_network_arc!(ttg, supplier1, xdock, supp1_to_plat)
    @test ne(ttg.graph) == 3
    # 2 is supplier1 on step 1, 6 is xdock on step 0, and so on
    @test has_edge(ttg.graph, 2, 6)
    @test has_edge(ttg.graph, 3, 7)
    @test has_edge(ttg.graph, 4, 8)
    @test srcs == [2, 3, 4]
    @test dsts == [6, 7, 8]

    I, J, arcs, costs = Int[], Int[], OFOND.NetworkArc[], Float64[]
    OFOND.add_arc_to_vectors!((I, J, arcs, costs), srcs, dsts, supp1_to_plat)
    @test I == [2, 3, 4]
    @test J == [6, 7, 8]
    @test arcs == [supp1_to_plat, supp1_to_plat, supp1_to_plat]
    @test arcs[1] === supp1_to_plat
    @test costs == fill(OFOND.EPS, 3)
end

# Test constructor from network and bundles

ttg = OFOND.TravelTimeGraph(network, bundles)
# Organizing idxs to have supp1, supp2, ... as above
allNodes = vcat(
    fill(supplier1, 4), fill(supplier2, 2), fill(xdock, 4), fill(port_l, 4), fill(plant, 1)
)
allSteps = [0, 1, 2, 3, 0, 1, 0, 1, 2, 3, 0, 1, 2, 3, 0]
xdockIdxs = findall(n -> n == xdock, ttg.networkNodes)
portIdxs = findall(n -> n == port_l, ttg.networkNodes)
common = vcat(xdockIdxs, portIdxs)
allIdxs = [ttg.hashToIdx[hash(step, node.hash)] for (step, node) in zip(allSteps, allNodes)]
@testset "Complete Constructor" begin
    # Nodes : 4 supplier1, 2 supplier2, 4 xdock, 4 port_l, 1 plant
    @test nv(ttg.graph) == 15
    @test ttg.networkNodes[allIdxs] == allNodes
    @test ttg.stepToDel[allIdxs] == allSteps
    # to test equality permutation free i sort the vectors
    @test sort(ttg.commonNodes) == sort(common)

    # Arcs : 3 supp1-xdock, 1 supp2-xdock, 1 supp1-plant, 1 supp2-plant, 1 xdock-plant, 1 port-plant, 3 xdock-port, 4 shortcuts
    @test ne(ttg.graph) == 15
    I = vcat(
        allIdxs[2:4],
        [allIdxs[6], allIdxs[3], allIdxs[6], allIdxs[8], allIdxs[12]],
        allIdxs[8:10],
        allIdxs[2:4],
        [allIdxs[6]],
    )
    J = vcat(
        allIdxs[7:9],
        [allIdxs[7], allIdxs[end], allIdxs[end], allIdxs[end], allIdxs[end]],
        allIdxs[11:13],
        allIdxs[1:3],
        [allIdxs[5]],
    )
    V = vcat(
        fill(supp1_to_plat, 3),
        supp2_to_plat,
        supp1_to_plant,
        supp2_to_plant,
        plat_to_plant,
        port_to_plant,
        fill(xdock_to_port, 3),
        fill(OFOND.SHORTCUT, 4),
    )
    @test [ttg.networkArcs[i, j] for (i, j) in zip(I, J)] == V

    # Bundle info
    @test ttg.bundleSrc == [allIdxs[3], allIdxs[6], allIdxs[4]]
    @test ttg.bundleDst == fill(allIdxs[end], 3)
end

# Test is_property functions
@testset "is_property functions" begin
    @test OFOND.is_path_elementary(ttg, allIdxs[[1, 7, 11, 15]])
    @test !OFOND.is_path_elementary(ttg, allIdxs[[1, 2, 7, 11, 15]])

    @test OFOND.is_platform(ttg, allIdxs[7])
    @test !OFOND.is_platform(ttg, allIdxs[1])

    @test OFOND.is_port(ttg, allIdxs[11])
    @test !OFOND.is_port(ttg, allIdxs[end])
end

supp1FromDel3 = ttg.hashToIdx[hash(3, supplier1.hash)]
supp1FromDel2 = ttg.hashToIdx[hash(2, supplier1.hash)]
supp1FromDel1 = ttg.hashToIdx[hash(1, supplier1.hash)]

xdockFromDel2 = ttg.hashToIdx[hash(2, xdock.hash)]
xdockFromDel1 = ttg.hashToIdx[hash(1, xdock.hash)]

portFromDel1 = ttg.hashToIdx[hash(1, port_l.hash)]
plantFromDel0 = ttg.hashToIdx[hash(0, plant.hash)]
TTPath = [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]

@testset "remove shortcuts" begin
    path = [supp1FromDel3, supp1FromDel2, xdockFromDel1]
    OFOND.remove_shortcuts!(path, ttg)
    @test path == [supp1FromDel2, xdockFromDel1]
    path = [supp1FromDel3, supp1FromDel2, supp1FromDel1, plantFromDel0]
    OFOND.remove_shortcuts!(path, ttg)
    @test path == [supp1FromDel1, plantFromDel0]
    OFOND.remove_shortcuts!(TTPath, ttg)
    @test TTPath == [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]
end

supp2FromDel1 = ttg.hashToIdx[hash(1, supplier2.hash)]

@testset "shortest path" begin
    I, J, V = findnz(ttg.costMatrix)
    addedCost = zeros(Base.size(ttg.costMatrix))
    for (i, j) in zip(I, J)
        addedCost[i, j] += 100
    end
    addedCost[supp1FromDel3, xdockFromDel2] = 10
    addedCost[xdockFromDel2, portFromDel1] = 10
    addedCost[portFromDel1, plantFromDel0] = 10
    ttg.costMatrix .+= addedCost
    @test OFOND.shortest_path(ttg, supp1FromDel3, plantFromDel0) == (TTPath, 30 + 3e-5)
    ttg.costMatrix[supp1FromDel3, supp1FromDel2] = 10 + 1e-5
    ttg.costMatrix[supp1FromDel2, plantFromDel0] = 10 + 1e-5
    @test OFOND.shortest_path(ttg, supp1FromDel3, plantFromDel0) ==
        ([supp1FromDel2, plantFromDel0], 20 + 1e-5)
    @test OFOND.shortest_path(ttg, supp2FromDel1, plantFromDel0) ==
        ([supp2FromDel1, plantFromDel0], 100 + 1e-5)
end

@testset "New node index" begin
    network2 = OFOND.NetworkGraph()
    OFOND.add_node!(network2, supplier1)
    OFOND.add_node!(network2, xdock)
    OFOND.add_node!(network2, plant)
    OFOND.add_arc!(network2, xdock, plant, plat_to_plant)
    OFOND.add_arc!(network2, supplier1, xdock, supp1_to_plat)
    OFOND.add_arc!(network2, supplier1, plant, supp1_to_plant)
    ttg2 = OFOND.TravelTimeGraph(network2, [OFOND.change_idx(bundle3, 1)])
    @test OFOND.new_node_index(ttg2, ttg, supp1FromDel3) == supp1FromDel3 == 4
    @test OFOND.new_node_index(ttg2, ttg, xdockFromDel2) != xdockFromDel2
    @test OFOND.new_node_index(ttg2, ttg, xdockFromDel2) == 7
    @test OFOND.new_node_index(ttg2, ttg, plantFromDel0) != plantFromDel0
    @test OFOND.new_node_index(ttg2, ttg, plantFromDel0) == 9
    @test OFOND.new_node_index(ttg2, ttg, portFromDel1) == -1
end