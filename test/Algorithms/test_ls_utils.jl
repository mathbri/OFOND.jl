@testset "Bin candidate" begin
    # 0 or 1 bin
    @test !OFOND.is_bin_candidate(OFOND.Bin[], xdock_to_port; skipLinear=false)
    @test !OFOND.is_bin_candidate([OFOND.Bin(50, 0)], xdock_to_port; skipLinear=true)
    # linear arc with skipLinear option
    @test !OFOND.is_bin_candidate(
        [OFOND.Bin(25, 25, [commodity1, commodity2])], supp_to_plat; skipLinear=true
    )
    @test OFOND.is_bin_candidate(
        [
            OFOND.Bin(25, 25, [commodity1, commodity2]),
            OFOND.Bin(25, 25, [commodity1, commodity2]),
        ],
        supp_to_plat,
        skipLinear=false,
    )
    # nonlinear arc with no gap in lower bound
    @test !OFOND.is_bin_candidate(
        [
            OFOND.Bin(20, 30, [commodity2, commodity2]),
            OFOND.Bin(20, 30, [commodity2, commodity2]),
        ],
        xdock_to_port;
        skipLinear=true,
    )
    @test OFOND.is_bin_candidate(
        [
            OFOND.Bin(25, 25, [commodity1, commodity2]),
            OFOND.Bin(25, 25, [commodity1, commodity2]),
        ],
        xdock_to_port,
        skipLinear=false,
    )
end

commodity3 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 10, 0.2))
commodity4 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 25, 0.5))
commodity5 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 20, 0.4))
commodity6 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 35, 0.7))
commodity7 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 5, 0.1))
commodity8 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 15, 0.3))
commodity9 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 40, 0.8))
commodity10 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 20, 0.4))
coms = [commodity3, commodity4, commodity5, commodity6, commodity7, commodity8, commodity9]

@testset "Bin recomputation" begin
    # two instances : 
    # one where ffd is better 
    newBins = OFOND.compute_new_bins(xdock_to_port, coms; sorted=false)
    @test newBins == [
        OFOND.Bin(0, 40, [commodity9, commodity3]),
        OFOND.Bin(0, 50, [commodity6, commodity8]),
        OFOND.Bin(0, 50, [commodity4, commodity5, commodity7]),
    ]
    # and the other where bfd is better
    push!(coms, commodity10)
    newBins = OFOND.compute_new_bins(xdock_to_port, coms; sorted=true)
    @test newBins == [
        OFOND.Bin(10, 40, [commodity3, commodity4, commodity7]),
        OFOND.Bin(10, 40, [commodity5, commodity10]),
        OFOND.Bin(0, 50, [commodity6, commodity8]),
        OFOND.Bin(10, 40, [commodity9]),
    ]
    @test OFOND.tentative_first_fit(OFOND.Bin[], 50, coms) == 5
end

# Creating workingArcs matrix
supp1Step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]
TSPath = [supp1Step2, xdockStep3, portStep4, plantStep1]

workingArcs = zeros(Bool, 20, 20)
workingArcs[supp1Step2, xdockStep3] = true
workingArcs[xdockStep3, portStep4] = true
workingArcs[portStep4, plantStep1] = true
workingArcs = sparse(workingArcs)

@testset "Save and revert bins" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    previousBins = OFOND.save_previous_bins(sol, workingArcs)
    I, J, V = findnz(previousBins)
    @test I == [supp1Step2, xdockStep3, portStep4]
    @test J == [xdockStep3, portStep4, plantStep1]
    @test V == fill(OFOND.Bin[], 3)

    OFOND.add_order!(sol, TSGraph, TSPath, order1)
    previousBins = OFOND.save_previous_bins(sol, workingArcs)
    I, J, V = findnz(previousBins)
    @test I == [supp1Step2, xdockStep3, portStep4]
    @test J == [xdockStep3, portStep4, plantStep1]
    @test V == fill(OFOND.Bin(30, 20, [commodity1, commodity1]), 3)

    OFOND.revert_bins!(sol, sparse(I, J, fill(OFOND.Bin[], 3)))
    @test sol.bins[supp1Step2, xdockStep3] == OFOND.Bin[]
    @test sol.bins[xdockStep3, portStep4] == OFOND.Bin[]
    @test sol.bins[portStep4, plantStep1] == OFOND.Bin[]

    OFOND.revert_bins!(sol, previousBins)
    @test sol.bins[supp1Step2, xdockStep3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[xdockStep3, portStep4] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
end

@testset "Save and remove bundle" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # add order 1 for bundle1 
    OFOND.add_order!(sol, TSGraph, TSPath, order1)
    # add order2 for bundle2 on different paths 
    supp2Step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
    TSPath2 = [supp2Step4, plantStep1]
    OFOND.add_order!(sol, TSGraph, TSPath2, order2)
    # add commodity3 on bundle1 path to check just the order removal 
    push!(sol.bins[supp1Step2, xdockStep3], OFOND.Bin(45, 5, [commodity3]))
    push!(sol.bins[xdockStep3, portStep4], OFOND.Bin(45, 5, [commodity3]))
    push!(sol.bins[portStep4, plantStep1], OFOND.Bin(45, 5, [commodity3]))

    previousBins, costRemoved = OFOND.save_and_remove_bundle!(
        sol, instance, [bundle1], [TTPath]
    )
    I, J, V = findnz(previousBins)
    @test I == [supp1Step2, xdockStep3, portStep4]
    @test J == [xdockStep3, portStep4, plantStep1]
    @test V == fill(
        [OFOND.Bin(30, 20, [commodity1, commodity1]), OFOND.Bin(45, 5, [commodity3])], 3
    )
    @test sol.bins[supp1Step2, xdockStep3] == [OFOND.Bin(45, 5, [commodity3])]
    @test sol.bins[xdockStep3, portStep4] == [OFOND.Bin(45, 5, [commodity3])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(45, 5, [commodity3])]
    @test sol.bins[supp2Step4, plantStep1] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
    @test costRemoved ≈ 0.0
end

# @testset "Best re-insertion" begin
#     #
# end

@testset "Node selection" begin
    @test !OFOND.are_nodes_candidate(TTGraph, 20, 20)
    @test OFOND.are_nodes_candidate(TTGraph, 1, 2)
    # add second port to check second false case
    network2 = deepcopy(network)
    port_d = OFOND.NetworkNode("005", :port_d, "PortL2", LLA(3, 3), "FR", "EU", true, 0.0)
    OFOND.add_node!(network2, port_d)
    TTGraph2 = OFOND.TravelTimeGraph(network2, bundles)
    portlFromDel2 = TTGraph2.hashToIdx[hash(2, port_l.hash)]
    portdFromDel1 = TTGraph2.hashToIdx[hash(1, port_d.hash)]
    @test !OFOND.are_nodes_candidate(TTGraph2, portlFromDel2, portdFromDel1)
    # testing select two nodes only gives condidate nodes
    randCount, selectCount = 0, 0
    for _ in 1:100
        node1, node2 = OFOND.select_two_nodes(TTGraph2)
        OFOND.are_nodes_candidate(TTGraph2, node1, node2) && (selectCount += 1)
        node1, node2 = rand(TTGraph.commonNodes, 2)
        OFOND.are_nodes_candidate(TTGraph2, node1, node2) && (randCount += 1)
    end
    @test randCount < 50
    @test selectCount == 100
end

@testset "Bundle and Path selection" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.greedy!(sol, instance)
    # Bundle selection
    @test OFOND.get_bundles_to_update(sol, plantFromDel0) == [bundle1, bundle2, bundle3]
    @test OFOND.get_bundles_to_update(sol, xdockFromDel1) == [bundle1, bundle3]
    @test OFOND.get_bundles_to_update(sol, xdockFromDel1, plantFromDel0) ==
        [bundle1, bundle3]
    @test OFOND.get_bundles_to_update(sol, xdockFromDel2, plantFromDel0) == OFOND.Bundle[]
    # Path selection
    @test OFOND.get_paths_to_update(sol, [bundle1], xdockFromDel1, plantFromDel0) ==
        [[xdockFromDel1, plantFromDel0]]
    @test OFOND.get_paths_to_update(
        sol, [bundle1, bundle3], supp1FromDel2, xdockFromDel1
    ) == [[supp1FromDel2, xdockFromDel1], [supp1FromDel2, xdockFromDel1]]
end
