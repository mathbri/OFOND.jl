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

supplier1 = OFOND.NetworkNode("001", :supplier, "", LLA(0, 0), "", "", true, 0)
supplier2 = OFOND.NetworkNode("002", :supplier, "", LLA(0, 0), "", "", true, 0)
xdock = OFOND.NetworkNode("002", :xdock, "", LLA(0, 0), "", "", true, 0)
plant = OFOND.NetworkNode("003", :plant, "", LLA(0, 0), "", "", true, 0)

plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
supp2FromDel2 = TTGraph.hashToIdx[hash(2, supplier2.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]

@testset "Paths utilities" begin
    # add node to path
    path = OFOND.NetworkNode[]
    OFOND.add_node_to_path!(path, supplier1, 1)
    @test path == [supplier1]
    OFOND.add_node_to_path!(path, xdock, 3)
    @test path == [supplier1, zero(OFOND.NetworkNode), xdock]
    OFOND.add_node_to_path!(path, plant, 2)
    @test path == [supplier1, plant, xdock]
    # check paths
    paths = [[supplier1, plant, xdock], [], [supplier1, zero(OFOND.NetworkNode), xdock]]
    @test_warn [
        "Found 1 empty paths for bundles [2]", "Missing points in 1 paths for bundles [3]"
    ] OFOND.check_paths(paths)
    # projectable onto TTGraph
    @test !OFOND.is_path_projectable([supplier1, zero(OFOND.NetworkNode), xdock])
    @test !OFOND.is_path_projectable(OFOND.NetworkNode[])
    @test OFOND.is_path_projectable([supplier1, plant, xdock])
    # find next node
    @test OFOND.find_next_node(TTGraph, plantFromDel0, supplier1) == supp1FromDel2
    @test OFOND.find_next_node(TTGraph, plantFromDel0, xdock) == xdockFromDel1
    @test OFOND.find_next_node(TTGraph, xdockFromDel1, supplier1) == supp1FromDel2
    warnNode = OFOND.NetworkNode("account", :supplier, "n2", LLA(2, 2), "c", "c", true, 1.1)
    @test OFOND.find_next_node(TTGraph, plantFromDel0, warnNode) === nothing
end

@testset "Project and repair" begin
    # project path
    ttPath, errors = OFOND.project_path([supplier2, xdock, plant], TTGraph, 1)
    @test !errors
    @test ttPath == [supp2FromDel2, xdockFromDel1, plantFromDel0]
    ttPath, errors = @test_warn "Next node not found, path not projectable for bundle 1" OFOND.project_path(
        [supplier2, OFOND.zero(OFOND.NetworkNode), plant], TTGraph, 1
    )
    @test errors
    @test ttPath == [plant]
    # all paths
    paths = [[supplier2, xdock, plant], [supplier1, zero(OFOND.NetworkNode), plant]]
    @test OFOND.project_all_paths(paths, TTGraph) ==
        [[supp2FromDel2, xdockFromDel1, plantFromDel0], []]
    paths = [[supplier2, xdock, plant], [supplier1, plant, xdock]]
    allPaths = @test_warn "Next node not found, path not projectable for bundle 2" OFOND.project_all_paths(
        paths, TTGraph
    )
    @test allPaths == [[supp2FromDel2, xdockFromDel1, plantFromDel0], []]
    # repair paths
    OFOND.repair_paths!(allPaths, instance)
    @test allPaths ==
        [[supp2FromDel2, xdockFromDel1, plantFromDel0], [supp1FromDel2, plantFromDel0]]
end

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