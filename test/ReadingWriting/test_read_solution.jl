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
    bundle3Test = OFOND.Bundle(supplier2, plant, [order1], 1, bunH1, 15, 2)
    @testset "Bundle 3 test equality - $(field)" for field in fieldnames(OFOND.Bundle)
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
    paths = [
        [supplier1, plant, xdock],
        OFOND.NetworkNode[],
        [supplier1, zero(OFOND.NetworkNode), xdock],
    ]
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
    @test ttPath == [plantFromDel0]
    # all paths
    paths = [[supplier2, xdock, plant], [supplier1, zero(OFOND.NetworkNode), plant]]
    @test OFOND.project_all_paths(paths, TTGraph) ==
        [[supp2FromDel2, xdockFromDel1, plantFromDel0], []]
    paths = [[supplier2, xdock, plant], [supplier1, plant, xdock]]
    allPaths = @test_warn "Next node not found, path not projectable for bundle 2" OFOND.project_all_paths(
        paths, TTGraph
    )
    @test allPaths == [[supp2FromDel2, xdockFromDel1, plantFromDel0], Int[]]
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
    supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
    @test sol.bundlePaths ==
        [[supp2FromDel1, plantFromDel0], [supp1FromDel2, xdockFromDel1, plantFromDel0]]
    @test sol.bundlesOnNode[xdockFromDel1] == [bundle2]
    @test sol.bundlesOnNode[plantFromDel0] == [bundle1, bundle2]
    supp2step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
    plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]
    supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
    xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
    xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]
    plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]
    @test sol.bins[supp2step4, plantStep1] == [OFOND.Bin(20, 30, [commodity1, commodity1])]
    supp1step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
    @test sol.bins[supp1step3, xdockStep4] == [OFOND.Bin(25, 25, [commodity3, commodity2])]
    @test sol.bins[xdockStep4, plantStep1] == [OFOND.Bin(25, 25, [commodity3, commodity2])]
    supp1step4 = TSGraph.hashToIdx[hash(4, supplier1.hash)]
    @test sol.bins[supp1step4, xdockStep1] == [OFOND.Bin(25, 25, [commodity5, commodity4])]
    @test sol.bins[xdockStep1, plantStep2] == [OFOND.Bin(25, 25, [commodity5, commodity4])]
end