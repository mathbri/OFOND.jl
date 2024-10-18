# Test constructor for TimeSpaceGraph structure
@testset "Constructors" begin
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

# Testing constructor sub Methods

# Test add_network_node!
tsg = OFOND.TimeSpaceGraph(4)
@testset "Add network node" begin
    # Adding supplier 1
    OFOND.add_network_node!(tsg, supplier1)
    @test nv(tsg.graph) == 4
    @test all(n -> n === supplier1, tsg.networkNodes)
    @test tsg.timeStep == [1, 2, 3, 4]
    @test [tsg.hashToIdx[hash(i, supplier1.hash)] for i in 1:4] == [1, 2, 3, 4]
    # Adding plant
    OFOND.add_network_node!(tsg, plant)
    @test nv(tsg.graph) == 8
    @test all(n -> n === plant, tsg.networkNodes[5:8])
    @test tsg.timeStep[5:8] == [1, 2, 3, 4]
    @test [tsg.hashToIdx[hash(i, plant.hash)] for i in 1:4] == [5, 6, 7, 8]
end

# Test add_network_arc!
@testset "Add network arc" begin
    # Adding supplier1-plant
    srcs, dsts = OFOND.add_network_arc!(tsg, supplier1, plant, supp1_to_plant)
    @test ne(tsg.graph) == 4
    @test has_edge(tsg.graph, 1, 7)
    @test has_edge(tsg.graph, 2, 8)
    @test has_edge(tsg.graph, 3, 5)
    @test has_edge(tsg.graph, 4, 6)
    @test srcs == [1, 2, 3, 4]
    @test dsts == [7, 8, 5, 6]
    # Adding it to vectors
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
    fill(supplier1, 4),
    fill(supplier2, 4),
    fill(supplier3, 4),
    fill(xdock, 4),
    fill(port_l, 4),
    fill(plant, 4),
)
allSteps = repeat([1, 2, 3, 4], 6)
allIdxs = [tsg.hashToIdx[hash(step, node.hash)] for (step, node) in zip(allSteps, allNodes)]
@testset "Complete constructor" begin
    # Nodes : 4 of each
    @test nv(tsg.graph) == 24
    @test tsg.networkNodes == allNodes
    @test tsg.timeStep == allSteps
    # Arcs : 4 times each
    @test ne(tsg.graph) == 36
    @test length(tsg.commonArcs) == 12
    I, J, Arc = findnz(tsg.networkArcs)
    # 4 supplier1->plant + 4 supplier1->xdock
    idxs = findall(i -> tsg.networkNodes[i] == supplier1, I)
    Is, Js, Arcs = I[idxs], J[idxs], Arc[idxs]
    @test Is == [4, 1, 2, 3, 3, 4, 1, 2]
    @test Js == [13, 14, 15, 16, 21, 22, 23, 24]
    @test Arcs == vcat(fill(supp1_to_plat, 4), fill(supp1_to_plant, 4))
    # 4 supplier2->plant + 4 supplier2->xdock
    idxs = findall(i -> tsg.networkNodes[i] == supplier2, I)
    Is, Js, Arcs = I[idxs], J[idxs], Arc[idxs]
    @test Is == [8, 5, 6, 7, 8, 5, 6, 7]
    @test Js == [13, 14, 15, 16, 21, 22, 23, 24]
    @test Arcs == vcat(fill(supp2_to_plat, 4), fill(supp2_to_plant, 4))
    # 4 supplier3->plant + 4 supplier3->xdock
    idxs = findall(i -> tsg.networkNodes[i] == supplier3, I)
    Is, Js, Arcs = I[idxs], J[idxs], Arc[idxs]
    @test Is == [12, 9, 10, 11, 11, 12, 9, 10]
    @test Js == [13, 14, 15, 16, 21, 22, 23, 24]
    @test Arcs == vcat(fill(supp3_to_plat, 4), fill(supp3_to_plant, 4))
    # 4 xdock->port + 4 xdock->plant
    idxs = findall(i -> tsg.networkNodes[i] == xdock, I)
    Is, Js, Arcs = I[idxs], J[idxs], Arc[idxs]
    @test Is == [16, 13, 14, 15, 16, 13, 14, 15]
    @test Js == [17, 18, 19, 20, 21, 22, 23, 24]
    @test Arcs == vcat(fill(xdock_to_port, 4), fill(plat_to_plant, 4))
    # 4 port->plant
    idxs = findall(i -> tsg.networkNodes[i] == port_l, I)
    Is, Js, Arcs = I[idxs], J[idxs], Arc[idxs]
    @test Is == [20, 17, 18, 19]
    @test Js == [21, 22, 23, 24]
    @test Arcs == fill(port_to_plant, 4)
end

@testset "is_path_elementary" begin
    @test OFOND.is_path_elementary(tsg, allIdxs[[1, 10, 15, 19]])
    @test !OFOND.is_path_elementary(tsg, allIdxs[[1, 2, 10, 15, 19]])
end