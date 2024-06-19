instance = OFOND.read_instance(
    joinpath(@__DIR__, "dummy_nodes.csv"),
    joinpath(@__DIR__, "dummy_legs.csv"),
    joinpath(@__DIR__, "dummy_commodities.csv"),
)
OFOND.add_properties(instance, (x, y, z) -> 2)
# Changing properties to made up ones
bundle11 = OFOND.Bundle(
    bundle1.supplier, bundle1.customer, bundle1.orders, 1, bundle1.hash, 15, 2
)
bundle22 = OFOND.Bundle(
    bundle2.supplier, bundle2.customer, bundle2.orders, 2, bundle2.hash, 15, 3
)
TTGraph = OFOND.TravelTimeGraph(instance.networkGraph, [bundle11, bundle22])
TSGraph = OFOND.TimeSpaceGraph(instance.networkGraph, 4)
instance = OFOND.Instance(
    instance.networkGraph,
    TTGraph,
    TSGraph,
    [bundle11, bundle22],
    instance.timeHorizon,
    instance.dateHorizon,
)

@testset "Solution row readers" begin
    rows = [
        row for row in CSV.File(
            joinpath(@__DIR__, "dummy_solution.csv");
            types=Dict(
                "supplier_account" => String,
                "customer_account" => String,
                "point_account" => String,
                "point_number" => Int,
            ),
        )
    ]
    # check bundle
    bundle1 = @test_warn "Bundle unknown in the instance" OFOND.check_bundle(
        instance, rows[1]
    )
    @test bundle1 === nothing
    bundle2 = @test_warn "Bundle unknown in the instance" OFOND.check_bundle(
        instance, rows[2]
    )
    @test bundle2 === nothing
    bundle3 = OFOND.check_bundle(instance, rows[4])
    bundle3Test = OFOND.Bundle(supplier2, plant, [order2], 1, bunH1, 0, 0)
    @testset "Bundle 3 test fields equality" for field in fieldnames(OFOND.Bundle)
        @test getfield(bundle3, field) == getfield(bundle3Test, field)
    end
    # check node
    node1 = @test_warn "Node unknown in the network" OFOND.check_node(instance, rows[3])
    @test node1 === nothing
    node2 = OFOND.check_node(instance, rows[4])
    node2Test = OFOND.NetworkNode(
        "003", :plant, "Plant1", LLA(4, 4), "FR", "EU", false, 0.0
    )
    @testset "Node 2 test fields equality" for field in fieldnames(OFOND.NetworkNode)
        @test getfield(node2, field) == getfield(node2Test, field)
    end
end

node11 = OFOND.NetworkNode("001", :supplier, "", LLA(0, 0), "", "", true, 0)
node12 = OFOND.NetworkNode("002", :supplier, "", LLA(0, 0), "", "", true, 0)
node2 = OFOND.NetworkNode("002", :xdock, "", LLA(0, 0), "", "", true, 0)
node3 = OFOND.NetworkNode("003", :plant, "", LLA(0, 0), "", "", true, 0)

plantFromDel0 = TTGraph.hashToIdx[hash(0, node3.hash)]
supp1FromDel2 = TTGraph.hashToIdx[hash(2, node11.hash)]
supp2FromDel2 = TTGraph.hashToIdx[hash(2, node12.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, node2.hash)]

@testset "Paths utilities" begin
    # add node to path
    path = OFOND.NetworkNode[]
    OFOND.add_node_to_path!(path, node11, 1)
    @test path == [node11]
    OFOND.add_node_to_path!(path, node2, 3)
    @test path == [node11, zero(OFOND.NetworkNode), node2]
    OFOND.add_node_to_path!(path, node3, 2)
    @test path == [node11, node3, node2]
    # check paths
    paths = [[node11, node3, node2], [], [node11, zero(OFOND.NetworkNode), node2]]
    @test_warn [
        "Found 1 empty paths for bundles [2]", "Missing points in 1 paths for bundles [3]"
    ] OFOND.check_paths(paths)
    # projectable onto TTGraph
    @test !OFOND.is_path_projectable([node11, zero(OFOND.NetworkNode), node2])
    @test !OFOND.is_path_projectable(OFOND.NetworkNode[])
    @test OFOND.is_path_projectable([node11, node3, node2])
    # find next node
    @test OFOND.find_next_node(TTGraph, plantFromDel0, node11) == supp1FromDel2
    @test OFOND.find_next_node(TTGraph, plantFromDel0, node2) == xdockFromDel1
    @test OFOND.find_next_node(TTGraph, xdockFromDel1, node11) == supp1FromDel2
    warnNode = OFOND.NetworkNode("account", :supplier, "n2", LLA(2, 2), "c", "c", true, 1.1)
    @test OFOND.find_next_node(TTGraph, plantFromDel0, warnNode) === nothing
end

@testset "Project and repair" begin
    # project path
    ttPath, errors = OFOND.project_path([node12, node2, node3], TTGraph, 1)
    @test !errors
    @test ttPath == [supp2FromDel2, xdockFromDel1, plantFromDel0]
    ttPath, errors = @test_warn "Next node not found, path not projectable for bundle 1" OFOND.project_path(
        [node12, OFOND.zero(OFOND.NetworkNode), node3], TTGraph, 1
    )
    @test errors
    @test ttPath == [node3]
    # all paths
    paths = [[node12, node2, node3], [node11, zero(OFOND.NetworkNode), node3]]
    @test OFOND.project_all_paths(paths, TTGraph) ==
        [[supp2FromDel2, xdockFromDel1, plantFromDel0], []]
    paths = [[node12, node2, node3], [node11, node3, node2]]
    allPaths = @test_warn "Next node not found, path not projectable for bundle 2" OFOND.project_all_paths(
        paths, TTGraph
    )
    @test allPaths == [[supp2FromDel2, xdockFromDel1, plantFromDel0], []]
    # repair paths
    OFOND.repair_paths!(allPaths, instance)
    @test allPaths ==
        [[supp2FromDel2, xdockFromDel1, plantFromDel0], [supp1FromDel2, plantFromDel0]]
end

bunH1 = hash(supplier2, hash(plant))
comData2 = OFOND.CommodityData("A123", 10, 2.5)
comData1 = OFOND.CommodityData("B456", 15, 3.5)
commodity1 = OFOND.Commodity(hash(1, bunH1), hash("B456"), comData1)
bunH2 = hash(supplier1, hash(plant))
commodity2 = OFOND.Commodity(hash(1, bunH2), hash("A123"), comData2)
commodity3 = OFOND.Commodity(hash(1, bunH2), hash("B456"), comData1)
commodity4 = OFOND.Commodity(hash(2, bunH2), hash("A123"), comData2)
commodity5 = OFOND.Commodity(hash(2, bunH2), hash("B456"), comData1)

@testset "Read solution" begin
    # read the whole solution
    sol = @test_warn [
        "Bundle unknown in the instance",
        "Bundle unknown in the instance",
        "Node unknown in the network",
    ] OFOND.read_solution(instance, joinpath(@__DIR__, "dummy_solution.csv"))
    @test sol.bundlePaths ==
        [[supp2FromDel2, plantFromDel0], [supp1FromDel2, xdockFromDel1, plantFromDel0]]
    @test sol.bundlesOnNode ==
        Dict(xdockFromDel1 => [bundle2], plantFromDel0 => [bundle1, bundle2])
    supp2step3 = TSGraph.hashToIdx[hash(3, supplier2.hash)]
    plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]
    supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
    supp1Step4 = TSGraph.hashToIdx[hash(4, supplier1.hash)]
    xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
    xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]
    plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]
    @test sol.bins[supp2step3, plantStep1] == [OFOND.Bin(20, 30, [commodity1, commodity1])]
    @test sol.bins[supp1step3, xdockStep4] == [OFOND.Bin(25, 25, [commodity2, commodity3])]
    @test sol.bins[xdockStep4, plantStep1] == [OFOND.Bin(25, 25, [commodity2, commodity3])]
    @test sol.bins[supp1step4, xdockStep1] == [OFOND.Bin(25, 25, [commodity4, commodity5])]
    @test sol.bins[xdockStep1, plantStep2] == [OFOND.Bin(25, 25, [commodity4, commodity5])]
end