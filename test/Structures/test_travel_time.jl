# Test constructor for TravelTimeGraph structure
@testset "Constructors" begin
    # Empty constructor
    ttg = OFOND.TravelTimeGraph()
    @test nv(ttg.graph) == 0
    @test isempty(ttg.networkNodes)
    @test isempty(ttg.stepToDel)
    # Constructor with vectors for sparse matrices
    I = [1, 2, 1]
    J = [3, 3, 2]
    arcs = [supp1_to_plant, plat_to_plant, supp1_to_plat]
    costs = [11.0, 4.0, 5.0]
    ttg = OFOND.TravelTimeGraph(ttg, I, J, arcs, costs)
    @test nv(ttg.graph) == 0
    @test ttg.costMatrix[1, 3] ≈ 11.0
    @test ttg.networkArcs[1, 3] === supp1_to_plant
    # Constructor with vector of bundles
    ttg = OFOND.TravelTimeGraph(bundles)
    @test nv(ttg.graph) == 0
    @test ttg.bundleSrc == ttg.bundleDst == fill(-1, 3)
    # Testing mutability
    @test !ismutable(ttg)
    @test ismutable(ttg.graph)
end

# Test bundle on nodes function
@testset "Bundle on nodes" begin
    # Bundle on nodes test
    @test OFOND.get_bundle_on_nodes(OFOND.Bundle[]) == Dict{UInt,Vector{OFOND.Bundle}}()
    @test OFOND.get_bundle_on_nodes([bundle1]) ==
        Dict(supplier1.hash => [bundle1], plant.hash => [bundle1])
    @test OFOND.get_bundle_on_nodes(bundles) == Dict(
        supplier1.hash => [bundle1],
        supplier2.hash => [bundle2],
        supplier3.hash => [bundle3],
        plant.hash => [bundle1, bundle2, bundle3],
    )
end

bundleOnNodes = OFOND.get_bundle_on_nodes(bundles)

# Test add timed node
@testset "Add timed node" begin
    # Add timed node test
    ttg = OFOND.TravelTimeGraph()
    # Adding supplier1 on time step 0
    nodeIdx = OFOND.add_timed_node!(ttg, supplier1, 0)
    # Related fields have been updated
    @test nv(ttg.graph) == 1
    @test ttg.networkNodes[1] === supplier1
    @test ttg.stepToDel[1] == 0
    @test ttg.hashToIdx[hash(0, supplier1.hash)] == 1
    @test nodeIdx == 1
    # Adding xdock on time step 1
    nodeIdx = OFOND.add_timed_node!(ttg, xdock, 1)
    @test nv(ttg.graph) == 2
    @test ttg.networkNodes[2] === xdock
    @test ttg.stepToDel[2] == 1
    @test ttg.hashToIdx[hash(1, xdock.hash)] == 2
    @test nodeIdx == 2
end

# Test add supplier / platform / plant node
@testset "Add typed node" begin
    ttg = OFOND.TravelTimeGraph(bundles)
    # Adding supplier 1 on time step 0
    OFOND.add_timed_supplier!(ttg, supplier1, 0, bundleOnNodes)
    # Hash to idx updated but not the bundle src as it is not a source of any bundle
    @test ttg.hashToIdx[hash(0, supplier1.hash)] == 1
    @test ttg.bundleSrc == fill(-1, 3)
    @test ttg.bundleDst == fill(-1, 3)
    @test ttg.commonNodes == Int[]
    # Adding supplier1 on time step 2
    OFOND.add_timed_supplier!(ttg, supplier1, 2, bundleOnNodes)
    @test ttg.hashToIdx[hash(2, supplier1.hash)] == 2
    @test ttg.bundleSrc == [2, -1, -1]
    @test ttg.bundleDst == fill(-1, 3)
    @test ttg.commonNodes == Int[]
    # Adding plant (always on on time step 0)
    OFOND.add_timed_customer!(ttg, plant, bundleOnNodes)
    @test ttg.hashToIdx[hash(0, plant.hash)] == 3
    @test ttg.bundleSrc == [2, -1, -1]
    @test ttg.bundleDst == [3, 3, 3]
    @test ttg.commonNodes == Int[]
    # Adding xdock on time step 0
    OFOND.add_timed_platform!(ttg, xdock, 0)
    @test ttg.hashToIdx[hash(0, xdock.hash)] == 4
    @test ttg.bundleSrc == [2, -1, -1]
    @test ttg.bundleDst == [3, 3, 3]
    @test ttg.commonNodes == [4]
end

ttg = OFOND.TravelTimeGraph(bundles)

# Test add network node
@testset "Add network node" begin
    # Adding supplier 1 : duplicated on time step 0, 1 and 2
    OFOND.add_network_node!(ttg, supplier1, bundleOnNodes, 4)
    @test nv(ttg.graph) == 3
    @test all(n -> n === supplier1, ttg.networkNodes)
    @test ttg.stepToDel == [0, 1, 2]
    @test ttg.bundleSrc == [3, -1, -1]
    @test ttg.bundleDst == fill(-1, 3)
    @test ttg.commonNodes == Int[]
    @test [ttg.hashToIdx[hash(i, supplier1.hash)] for i in 0:2] == [1, 2, 3]
    # Adding plant, duplicated one time
    OFOND.add_network_node!(ttg, plant, bundleOnNodes, 4)
    @test nv(ttg.graph) == 4
    @test ttg.networkNodes[4] === plant
    @test ttg.stepToDel[4] == 0
    @test ttg.hashToIdx[hash(0, plant.hash)] == 4
    @test ttg.bundleSrc == [3, -1, -1]
    @test ttg.bundleDst == [4, 4, 4]
    @test ttg.commonNodes == Int[]
    # Adding xdock : duplicated max time number of times
    OFOND.add_network_node!(ttg, xdock, bundleOnNodes, 4)
    @test nv(ttg.graph) == 9
    @test all(n -> n === xdock, ttg.networkNodes[5:end])
    @test ttg.stepToDel[5:end] == [0, 1, 2, 3, 4]
    @test ttg.bundleSrc == [3, -1, -1]
    @test ttg.bundleDst == [4, 4, 4]
    @test ttg.commonNodes == [5, 6, 7, 8, 9]
end

OFOND.add_network_node!(ttg, supplier3, bundleOnNodes, 4)

# Test add network arc
@testset "Add network arc" begin
    # Adding supplier1-xdock
    srcs, dsts = OFOND.add_network_arc!(ttg, supplier1, xdock, supp1_to_plat)
    @test ne(ttg.graph) == 2
    # 2 is supplier1 on step 1, 5 is xdock on step 0, and so on
    @test has_edge(ttg.graph, 2, 5)
    @test has_edge(ttg.graph, 3, 6)
    @test srcs == [2, 3]
    @test dsts == [5, 6]
    # Adding supplier3-xdock
    srcs, dsts = OFOND.add_network_arc!(ttg, supplier3, xdock, supp1_to_plat)
    @test ne(ttg.graph) == 5
    # 11 is supplier3 on step 1, 5 is xdock on step 0, and so on
    @test has_edge(ttg.graph, 11, 5)
    @test has_edge(ttg.graph, 12, 6)
    @test has_edge(ttg.graph, 13, 7)
    @test srcs == [11, 12, 13]
    @test dsts == [5, 6, 7]
end

OFOND.add_network_arc!(ttg, xdock, plant, plat_to_plant)
OFOND.add_network_arc!(ttg, supplier3, supplier3, OFOND.SHORTCUT)

# Test add arc to vectors 
@testset "Add arc to vectors" begin
    srcs = [11, 12, 13]
    dsts = [5, 6, 7]
    I, J, arcs, costs = Int[], Int[], OFOND.NetworkArc[], Float64[]
    OFOND.add_arc_to_vectors!((I, J, arcs, costs), srcs, dsts, supp3_to_plat)
    @test I == [11, 12, 13]
    @test J == [5, 6, 7]
    @test arcs == [supp3_to_plat, supp3_to_plat, supp3_to_plat]
    @test arcs[1] === supp3_to_plat
    @test costs == fill(OFOND.EPS, 3)
end

# Test add bundle arcs
@testset "Add bundle arcs" begin
    OFOND.add_bundle_arcs!(ttg, bundle3)
    @test ttg.bundleArcs[1] == Tuple{Int,Int}[]
    @test ttg.bundleArcs[2] == Tuple{Int,Int}[]
    @test ttg.bundleArcs[3] == [(6, 4), (12, 6), (13, 12)]
end

# Testing complete constructor
ttg = OFOND.TravelTimeGraph(network, bundles)
# Organizing idxs to have supp1, supp2, ... as above
allNodes = vcat(
    fill(supplier1, 3),
    fill(supplier2, 2),
    fill(supplier3, 4),
    fill(xdock, 4),
    fill(port_l, 4),
    fill(plant, 1),
)
allSteps = [0, 1, 2, 0, 1, 0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3, 0]
xdockIdxs = findall(n -> n == xdock, ttg.networkNodes)
portIdxs = findall(n -> n == port_l, ttg.networkNodes)
common = vcat(xdockIdxs, portIdxs)
allIdxs = [ttg.hashToIdx[hash(step, node.hash)] for (step, node) in zip(allSteps, allNodes)]
@testset "Complete Constructor" begin
    # Nodes : 3 supplier1, 2 supplier2, 4 supplier3, 4 xdock, 4 port_l, 1 plant
    @test nv(ttg.graph) == 18
    @test ttg.networkNodes[allIdxs] == allNodes
    @test ttg.stepToDel[allIdxs] == allSteps
    # sorting to test equality permutation free
    @test sort(ttg.commonNodes) == sort(common)
    # Arcs
    @test ne(ttg.graph) == 20
    I, J, Arc = findnz(ttg.networkArcs)
    # Common arcs : 1 xdock-plant, 1 port-plant, 3 xdock-port
    idxs = findall(a -> a.type in OFOND.COMMON_ARC_TYPES, Arc)
    Is, Js, Arcs = I[idxs], J[idxs], Arc[idxs]
    @test Is == [11, 12, 13, 11, 15]
    @test Js == [14, 15, 16, 18, 18]
    @test Arcs ==
        [xdock_to_port, xdock_to_port, xdock_to_port, plat_to_plant, port_to_plant]
    # Bundle 1 : 2 supp1-xdock + 1 supp1-plant 
    idxs = findall(i -> ttg.networkNodes[i] == supplier1, I)
    Is, Js, Arcs = I[idxs], J[idxs], Arc[idxs]
    @test Is == [2, 3, 2, 3, 3]
    @test Js == [1, 2, 10, 11, 18]
    @test Arcs ==
        [OFOND.SHORTCUT, OFOND.SHORTCUT, supp1_to_plat, supp1_to_plat, supp1_to_plant]
    @test ttg.bundleArcs[1] == [(3, 11), (3, 18), (11, 18)]
    # Bundle 2 : 1 supp2-xdock + 1 supp2-plant
    idxs = findall(i -> ttg.networkNodes[i] == supplier2, I)
    Is, Js, Arcs = I[idxs], J[idxs], Arc[idxs]
    @test Is == [5, 5, 5]
    @test Js == [4, 10, 18]
    @test Arcs == [OFOND.SHORTCUT, supp2_to_plat, supp2_to_plant]
    @test ttg.bundleArcs[2] == [(5, 18)]
    # Bundle 3 : 3 supp3-xdock + 1 supp3-plant
    idxs = findall(i -> ttg.networkNodes[i] == supplier3, I)
    Is, Js, Arcs = I[idxs], J[idxs], Arc[idxs]
    @test Is == [7, 8, 9, 7, 8, 9, 8]
    @test Js == [6, 7, 8, 10, 11, 12, 18]
    @test Arcs == [
        OFOND.SHORTCUT,
        OFOND.SHORTCUT,
        OFOND.SHORTCUT,
        supp3_to_plat,
        supp3_to_plat,
        supp3_to_plat,
        supp3_to_plant,
    ]
    @test ttg.bundleArcs[3] ==
        [(8, 11), (8, 18), (9, 8), (9, 12), (11, 18), (12, 15), (15, 18)]
    # Bundle info
    @test ttg.bundleSrc == [3, 5, 9]
    @test ttg.bundleDst == [18, 18, 18]
end

# Test is_property functions
@testset "is_property functions" begin
    @test OFOND.is_path_elementary(ttg, allIdxs[[1, 7, 11, 15]])
    @test !OFOND.is_path_elementary(ttg, allIdxs[[1, 2, 7, 11, 15]])

    @test OFOND.is_platform(ttg, allIdxs[10])
    @test !OFOND.is_platform(ttg, allIdxs[1])

    @test OFOND.is_port(ttg, allIdxs[14])
    @test !OFOND.is_port(ttg, allIdxs[end])
end

supp3FromDel3 = ttg.hashToIdx[hash(3, supplier3.hash)]
supp1FromDel2 = ttg.hashToIdx[hash(2, supplier1.hash)]
supp3FromDel2 = ttg.hashToIdx[hash(2, supplier3.hash)]
supp1FromDel1 = ttg.hashToIdx[hash(1, supplier1.hash)]

xdockFromDel2 = ttg.hashToIdx[hash(2, xdock.hash)]
xdockFromDel1 = ttg.hashToIdx[hash(1, xdock.hash)]

portFromDel1 = ttg.hashToIdx[hash(1, port_l.hash)]
plantFromDel0 = ttg.hashToIdx[hash(0, plant.hash)]
TTPath = [supp3FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]

@testset "remove shortcuts" begin
    path = [supp1FromDel2, supp1FromDel1, plantFromDel0]
    OFOND.remove_shortcuts!(path, ttg)
    @test path == [supp1FromDel1, plantFromDel0]
    OFOND.remove_shortcuts!(TTPath, ttg)
    @test TTPath == [supp3FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]
end

supp2FromDel1 = ttg.hashToIdx[hash(1, supplier2.hash)]

@testset "shortest path" begin
    I, J, V = findnz(ttg.costMatrix)
    addedCost = zeros(Base.size(ttg.costMatrix))
    for (i, j) in zip(I, J)
        addedCost[i, j] += 100
    end
    addedCost[supp3FromDel3, xdockFromDel2] = 10
    addedCost[xdockFromDel2, portFromDel1] = 10
    addedCost[portFromDel1, plantFromDel0] = 10
    ttg.costMatrix .+= addedCost
    @test OFOND.shortest_path(ttg, supp3FromDel3, plantFromDel0) == (TTPath, 30 + 3e-5)
    ttg.costMatrix[supp3FromDel3, supp3FromDel2] = 5.0 + 1e-5
    ttg.costMatrix[supp3FromDel2, plantFromDel0] = 5.0 + 1e-5
    @test OFOND.shortest_path(ttg, supp3FromDel3, plantFromDel0) ==
        ([supp3FromDel2, plantFromDel0], 10 + 1e-5)
    @test OFOND.shortest_path(ttg, supp2FromDel1, plantFromDel0) ==
        ([supp2FromDel1, plantFromDel0], 100 + 1e-5)
end

@testset "New node index" begin
    network2 = OFOND.NetworkGraph()
    OFOND.add_node!(network2, supplier3)
    OFOND.add_node!(network2, xdock)
    OFOND.add_node!(network2, plant)
    OFOND.add_arc!(network2, xdock, plant, plat_to_plant)
    OFOND.add_arc!(network2, supplier3, xdock, supp1_to_plat)
    OFOND.add_arc!(network2, supplier3, plant, supp1_to_plant)
    ttg2 = OFOND.TravelTimeGraph(network2, [OFOND.change_idx(bundle3, 1)])
    @test OFOND.new_node_index(ttg2, ttg, supp3FromDel3) == 4
    @test OFOND.new_node_index(ttg2, ttg, xdockFromDel2) != xdockFromDel2
    @test OFOND.new_node_index(ttg2, ttg, xdockFromDel2) == 7
    @test OFOND.new_node_index(ttg2, ttg, plantFromDel0) != plantFromDel0
    @test OFOND.new_node_index(ttg2, ttg, plantFromDel0) == 9
    @test OFOND.new_node_index(ttg2, ttg, portFromDel1) == -1
end