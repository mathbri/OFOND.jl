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
    bundleWarn = @test_warn "Bundle unknown in the instance" OFOND.check_bundle(
        instance, rows[1]
    )
    @test bundleWarn === nothing
    bundle2 = @test_warn "Bundle unknown in the instance" OFOND.check_bundle(
        instance, rows[2]
    )
    @test bundleWarn === nothing
    bundle1Read = OFOND.check_bundle(instance, rows[4])
    @testset "Bundle 1 - Read equality - $(field)" for field in fieldnames(OFOND.Bundle)
        @test getfield(bundle11, field) == getfield(bundle1Read, field)
    end
    # check node
    nodeWarn = @test_warn "Node unknown in the network" OFOND.check_node(instance, rows[3])
    @test nodeWarn === nothing
    node1 = OFOND.check_node(instance, rows[4])
    @testset "Node 1 - Plant equality" for field in fieldnames(OFOND.NetworkNode)
        @test getfield(node1, field) == getfield(plant, field)
    end
end

supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
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
        "Found 1 empty paths for bundles 2", "Missing points in 1 paths for bundles 3"
    ] OFOND.check_paths(paths)
    # projectable onto TTGraph
    @test !OFOND.is_path_projectable([supplier1, zero(OFOND.NetworkNode), xdock])
    @test !OFOND.is_path_projectable(OFOND.NetworkNode[])
    @test OFOND.is_path_projectable([supplier1, plant, xdock])
    # find next node
    @test OFOND.find_next_node(TTGraph, plantFromDel0, supplier1) == supp1FromDel2
    @test OFOND.find_next_node(TTGraph, plantFromDel0, xdock) == xdockFromDel1
    @test OFOND.find_next_node(TTGraph, xdockFromDel1, supplier1) == supp1FromDel2
    warnNode = OFOND.NetworkNode("account", :supplier, "c", "c", true, 1.1)
    @test OFOND.find_next_node(TTGraph, plantFromDel0, warnNode) === nothing
end

supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]

@testset "Project and repair" begin
    # project path
    ttPath, errors = OFOND.project_path([plant, xdock, supplier1], TTGraph, 1)
    @test !errors
    @test ttPath == [supp1FromDel2, xdockFromDel1, plantFromDel0]
    ttPath, errors = @test_warn "Next node not found, path not projectable for bundle 1" OFOND.project_path(
        [plant, OFOND.zero(OFOND.NetworkNode), supplier1], TTGraph, 1
    )
    @test errors
    @test ttPath == [plantFromDel0]
    # all paths
    paths = [[plant, xdock, supplier1], [plant, zero(OFOND.NetworkNode), supplier2]]
    @test OFOND.project_all_paths(paths, TTGraph) ==
        [[supp1FromDel2, xdockFromDel1, plantFromDel0], []]
    paths = [[plant, xdock, supplier1], [supplier2, plant, xdock]]
    allPaths = @test_warn "Next node not found, path not projectable for bundle 2" OFOND.project_all_paths(
        paths, TTGraph
    )
    @test allPaths == [[supp1FromDel2, xdockFromDel1, plantFromDel0], Int[]]
    # repair paths
    OFOND.repair_paths!(allPaths, instance)
    @test allPaths ==
        [[supp1FromDel2, xdockFromDel1, plantFromDel0], [supp2FromDel1, plantFromDel0]]
end

supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]

supp2step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]

supp1step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]

supp3step3 = TSGraph.hashToIdx[hash(3, supplier3.hash)]
supp3step4 = TSGraph.hashToIdx[hash(4, supplier3.hash)]
plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]

@testset "Read solution" begin
    # read the whole solution
    sol = @test_warn [
        "Bundle unknown in the instance",
        "Bundle unknown in the instance",
        "Node unknown in the network",
    ] OFOND.read_solution(instance, joinpath(@__DIR__, "dummy_solution.csv"))
    @test sol.bundlePaths ==
        [TTPath, [supp2FromDel1, plantFromDel0], [supp3FromDel2, plantFromDel0]]
    @test sol.bundlesOnNode[xdockFromDel1] == Int[]
    @test sol.bundlesOnNode[xdockFromDel2] == [1]
    @test sol.bundlesOnNode[plantFromDel0] == [1, 2, 3]

    @test sol.bins[supp2step4, plantStep1] == [OFOND.Bin(21, 30, [commodity2, commodity2])]

    @test sol.bins[supp1step2, xdockStep3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[xdockStep3, portStep4] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]

    @test sol.bins[supp3step3, plantStep1] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    @test sol.bins[supp3step4, plantStep2] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
end