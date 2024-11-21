@testset "Bin candidate" begin
    # 0 or 1 bin
    @test !OFOND.is_bin_candidate(OFOND.Bin[], xdock_to_port; skipLinear=false)
    @test !OFOND.is_bin_candidate([OFOND.Bin(50)], xdock_to_port; skipLinear=true)
    # linear arc with skipLinear option
    @test !OFOND.is_bin_candidate(
        [OFOND.Bin(25, 25, [commodity1, commodity2])], supp1_to_plat; skipLinear=true
    )
    @test OFOND.is_bin_candidate(
        [
            OFOND.Bin(25, 25, [commodity1, commodity2]),
            OFOND.Bin(25, 25, [commodity1, commodity2]),
        ],
        supp1_to_plat,
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

commodity4 = OFOND.Commodity(3, hash("A123"), 10, 0.2)
commodity5 = OFOND.Commodity(4, hash("A123"), 25, 0.5)
commodity6 = OFOND.Commodity(5, hash("A123"), 20, 0.4)
commodity7 = OFOND.Commodity(6, hash("A123"), 35, 0.7)
commodity8 = OFOND.Commodity(7, hash("A123"), 5, 0.1)
commodity9 = OFOND.Commodity(8, hash("A123"), 15, 0.3)
commodity10 = OFOND.Commodity(9, hash("A123"), 40, 0.8)
commodity11 = OFOND.Commodity(10, hash("A123"), 20, 0.4)

@testset "Bin recomputation" begin
    # two instances : 
    # one where ffd is better 
    coms = [
        commodity4, commodity5, commodity6, commodity7, commodity8, commodity9, commodity10
    ]
    newBins = OFOND.compute_new_bins(xdock_to_port, coms; sorted=false)
    @test newBins == [
        OFOND.Bin(0, 50, [commodity10, commodity4]),
        OFOND.Bin(0, 50, [commodity7, commodity9]),
        OFOND.Bin(0, 50, [commodity5, commodity6, commodity8]),
    ]
    # and the other where bfd is better
    coms = [
        commodity4, commodity5, commodity6, commodity7, commodity8, commodity9, commodity10
    ]
    push!(coms, commodity11)
    newBins = OFOND.compute_new_bins(xdock_to_port, coms; sorted=true)
    @test newBins == [
        OFOND.Bin(10, 40, [commodity4, commodity5, commodity8]),
        OFOND.Bin(10, 40, [commodity6, commodity11]),
        OFOND.Bin(0, 50, [commodity7, commodity9]),
        OFOND.Bin(10, 40, [commodity10]),
    ]
    @test OFOND.tentative_first_fit(OFOND.Bin[], 50, coms, CAPACITIES; sorted=true) == 5
end

# Creating workingArcs matrix
supp1Step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]
TSPath = [supp1Step2, xdockStep3, portStep4, plantStep1]

# workingArcs = zeros(Bool, size(TSGraph.networkArcs))
# workingArcs[supp1Step2, xdockStep3] = true
# workingArcs[xdockStep3, portStep4] = true
# workingArcs[portStep4, plantStep1] = true
workingArcs = sparse(
    [supp1Step2, xdockStep3, portStep4],
    [xdockStep3, portStep4, plantStep1],
    [true, true, true],
    nv(TSGraph.graph),
    nv(TSGraph.graph),
)

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
    @test V == fill([OFOND.Bin(30, 20, [commodity1, commodity1])], 3)

    OFOND.revert_bins!(sol, sparse(I, J, fill(OFOND.Bin[], 3)))
    @test sol.bins[supp1Step2, xdockStep3] == OFOND.Bin[]
    @test sol.bins[xdockStep3, portStep4] == OFOND.Bin[]
    @test sol.bins[portStep4, plantStep1] == OFOND.Bin[]

    OFOND.revert_bins!(sol, previousBins)
    @test sol.bins[supp1Step2, xdockStep3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[xdockStep3, portStep4] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
end

# @testset "Save and remove bundle" begin
#     sol = OFOND.Solution(TTGraph, TSGraph, bundles)
#     # add order 1 for bundle1 
#     OFOND.update_solution!(sol, instance, [bundle1], [TTPath])
#     # add order2 for bundle2 on different paths 
#     supp2fromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
#     plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
#     TTPath2 = [supp2fromDel1, plantFromDel0]
#     OFOND.update_solution!(sol, instance, [bundle2], [TTPath2])
#     # add commodity3 on bundle1 path to check just the order removal 
#     push!(sol.bins[supp1Step2, xdockStep3], OFOND.Bin(45, 5, [commodity3]))
#     push!(sol.bins[xdockStep3, portStep4], OFOND.Bin(45, 5, [commodity3]))
#     push!(sol.bins[portStep4, plantStep1], OFOND.Bin(45, 5, [commodity3]))

#     previousBins, costRemoved = OFOND.save_and_remove_bundle!(
#         sol, instance, [bundle1], [TTPath]
#     )
#     I, J, V = findnz(previousBins)
#     @test I == [supp1Step2, xdockStep3, portStep4]
#     @test J == [xdockStep3, portStep4, plantStep1]
#     @test V == fill(
#         [OFOND.Bin(30, 20, [commodity1, commodity1]), OFOND.Bin(45, 5, [commodity3])], 3
#     )
#     # empty bins not cleared by default on linear arcs
#     @test sol.bins[supp1Step2, xdockStep3] ==
#         [OFOND.Bin(50), OFOND.Bin(45, 5, [commodity3])]
#     @test sol.bins[xdockStep3, portStep4] == [OFOND.Bin(45, 5, [commodity3])]
#     @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(45, 5, [commodity3])]
#     @test sol.bins[supp2Step4, plantStep1] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
#     @test costRemoved ≈ -24.608
# end

# @testset "Both re-insertion" begin
#     sol = OFOND.Solution(TTGraph, TSGraph, bundles)
#     # direct arc so need to have > 1 truck of space left for it to be 0
#     append!(sol.bins[supp1Step3, plantStep1], fill(OFOND.Bin(9), 6))
#     # lb will count 0 with use_bins as greedy will count 1 new truck 
#     # lb path will be direct while greedy path will be via cross-dock
#     greedyPath, lowerBoundPath = OFOND.both_insertion(
#         sol, instance, bundle1, supp1FromDel2, plantFromDel0, CAPACITIES
#     )
#     @test greedyPath == [supp1FromDel2, xdockFromDel1, plantFromDel0]
#     @test lowerBoundPath == [supp1FromDel2, plantFromDel0]
# end

# @testset "Change solution" begin
#     sol = OFOND.Solution(TTGraph, TSGraph, bundles)
#     sol2 = OFOND.Solution(TTGraph, TSGraph, bundles)
#     OFOND.shortest_delivery!(sol2, instance)
#     # testing we have the right solution
#     @test sol2.bundlePaths == [
#         [supp1FromDel2, plantFromDel0],
#         [supp2fromDel1, plantFromDel0],
#         [supp1FromDel2, plantFromDel0],
#     ]
#     # lower bound and greedy give the same solution but for greedy we need to adapt properties
#     OFOND.lower_bound!(sol, instance)
#     # testing we have the right solution
#     @test sol.bundlePaths == [
#         [supp1FromDel2, xdockFromDel1, plantFromDel0],
#         [supp2fromDel1, plantFromDel0],
#         [supp1FromDel2, xdockFromDel1, plantFromDel0],
#     ]
#     # sol for bundle 3 becomes sol2, path for bundle2 already equal
#     OFOND.change_solution_to_other!(sol, sol2, instance, [bundle3])
#     @test sol.bundlePaths[1] != sol2.bundlePaths[1]
#     @test sol.bundlePaths[2] == sol2.bundlePaths[2]
#     @test sol.bundlePaths[3] == sol2.bundlePaths[3]
#     @test sol.bundlePaths == [
#         [supp1FromDel2, xdockFromDel1, plantFromDel0],
#         [supp2fromDel1, plantFromDel0],
#         [supp1FromDel2, plantFromDel0],
#     ]
#     # commodities in bundle 1 2 and 3 are the same but in real instances they will be different
#     # so removing bundle 3 when sharing arcs with bundle 1 remived all commodties, not just bundle3
#     # so adding bundle 1 again
#     OFOND.update_solution!(sol, instance, [bundle1], [[3, 8, 15]])
#     supp1step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
#     @test sol.bins[supp1step3, xdockStep4] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
#     @test sol.bins[supp1step3, plantStep1] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
#     supp1step4 = TSGraph.hashToIdx[hash(4, supplier1.hash)]
#     @test sol.bins[supp1step4, plantStep2] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
#     @test sol.bins[xdockStep4, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
#     supp2step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
#     @test sol.bins[supp2step4, plantStep1] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
# end

@testset "Node selection" begin
    @test !OFOND.are_nodes_candidate(TTGraph, 20, 20)
    @test !OFOND.are_nodes_candidate(TTGraph, 1, 2)
    @test !OFOND.are_nodes_candidate(TTGraph, 2, 1)
    @test !OFOND.are_nodes_candidate(TTGraph, 4, 5)
    @test OFOND.are_nodes_candidate(TTGraph, 3, 13)
    # add second port to check second false case
    network2 = deepcopy(network)
    port_d = OFOND.NetworkNode("005", :pod, "FR", "EU", true, 0.0)
    OFOND.add_node!(network2, port_d)
    TTGraph2 = OFOND.TravelTimeGraph(network2, bundles)
    portlFromDel2 = TTGraph2.hashToIdx[hash(2, port_l.hash)]
    portdFromDel1 = TTGraph2.hashToIdx[hash(1, port_d.hash)]
    @test !OFOND.are_nodes_candidate(TTGraph2, portlFromDel2, portdFromDel1)
    xdockFromDel2 = TTGraph2.hashToIdx[hash(2, xdock.hash)]
    portlFromDel1 = TTGraph2.hashToIdx[hash(1, port_l.hash)]
    xdockFromDel1 = TTGraph2.hashToIdx[hash(1, xdock.hash)]
    supp1FromDel1 = TTGraph2.hashToIdx[hash(1, supplier1.hash)]
    @test !OFOND.are_nodes_candidate(TTGraph2, xdockFromDel2, xdockFromDel1)
    @test OFOND.are_nodes_candidate(TTGraph2, xdockFromDel2, portlFromDel1)
    @test !OFOND.are_nodes_candidate(TTGraph2, xdockFromDel2, supp1FromDel1)
end

plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]
xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]

@testset "Bundle and Path selection" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # lower bound and greedy give the same solution but for greedy we need to adapt properties
    OFOND.lower_bound!(sol, instance)
    # Changing budle 2 to direct path 
    OFOND.update_solution!(sol, instance, bundle2; remove=true)
    OFOND.update_solution!(sol, instance, bundle2, [supp2FromDel1, plantFromDel0])
    # Node order 
    @test OFOND.is_node1_before_node2([0, 1, 2, 3], 1, 2)
    @test !OFOND.is_node1_before_node2([0, 1, 2, 3], 3, 2)
    # Bundle selection
    # With plants
    @test OFOND.get_bundles_to_update(TTGraph, sol, plantFromDel0) == [1, 3, 2]
    @test OFOND.get_bundles_to_update(TTGraph, sol, xdockFromDel1) == [1, 3]
    # Between common nodes
    @test OFOND.get_bundles_to_update(TTGraph, sol, xdockFromDel1, plantFromDel0) == [1, 3]
    @test OFOND.get_bundles_to_update(TTGraph, sol, plantFromDel0, xdockFromDel1) == Int[]
    @test OFOND.get_bundles_to_update(TTGraph, sol, xdockFromDel2, plantFromDel0) == Int[]
    # Between supplier and plant
    @test OFOND.get_bundles_to_update(TTGraph, sol, supp1FromDel3, plantFromDel0) == [1]
    @test OFOND.get_bundles_to_update(TTGraph, sol, supp1FromDel2, plantFromDel0) == Int[]
    @test OFOND.get_bundles_to_update(TTGraph, sol, supp2FromDel2, plantFromDel0) == [2]
    @test OFOND.get_bundles_to_update(TTGraph, sol, supp3FromDel3, plantFromDel0) == [3]
    # Path selection
    @test OFOND.get_paths_to_update(
        sol, [bundle1, bundle3], xdockFromDel1, plantFromDel0
    ) == [[xdockFromDel1, plantFromDel0], [xdockFromDel1, plantFromDel0]]
    @test OFOND.get_paths_to_update(sol, [bundle1], supp1FromDel2, xdockFromDel1) ==
        [[supp1FromDel2, xdockFromDel1]]
end

supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]

@testset "Bundle estimated removal cost" begin
    # Estimated transport unit
    bins = [OFOND.Bin(30), OFOND.Bin(30), OFOND.Bin(30), OFOND.Bin(30)]
    @test OFOND.estimated_transport_units(order11, bins) == 4
    bins = [
        OFOND.Bin(30, 15, [commodity1]),
        OFOND.Bin(30, 10, [commodity1]),
        OFOND.Bin(30, 5, [commodity1]),
        OFOND.Bin(30),
    ]
    @test OFOND.estimated_transport_units(order11, bins) == 3
    bins = [
        OFOND.Bin(30, 15, [commodity1]),
        OFOND.Bin(30, 10, [commodity1]),
        OFOND.Bin(30, 15, [commodity1]),
        OFOND.Bin(30),
    ]
    @test OFOND.estimated_transport_units(order11, bins) == 2
    # Full path estimated removal cost
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.lower_bound!(sol, instance)
    @test OFOND.bundle_estimated_removal_cost(
        bundle33, [supp3FromDel2, xdockFromDel1], instance, sol
    ) ≈ 16.346153846153847
    @test OFOND.bundle_estimated_removal_cost(
        bundle33, [supp3FromDel2, xdockFromDel1, plantFromDel0], instance, sol
    ) ≈ 37.34615384615385
end

@testset "Bundle fusing" begin
    # Fuse all bundles
    fusedBundle = OFOND.fuse_bundles(instance, bundles, CAPACITIES)
    @test fusedBundle.hash == UInt(0)
    # Supplier and customer are from bundle 1
    @test fusedBundle.supplier == bundle11.supplier
    @test fusedBundle.customer == bundle11.customer
    # Maximum delivery time and index are also from bundle 1
    @test fusedBundle.maxDelTime == bundle11.maxDelTime
    @test fusedBundle.idx == bundle11.idx
    # Maximum pack size comes from bundle 2
    @test fusedBundle.maxPackSize == bundle22.maxPackSize
    # Its first order comes from the fusing of order 1, 2 and 3
    @test fusedBundle.orders[1].bundleHash == UInt(0)
    @test fusedBundle.orders[1].deliveryDate == 1
    @test fusedBundle.orders[1].hash == hash(1, UInt(0))
    @test fusedBundle.orders[1].content ==
        [commodity2, commodity2, commodity2, commodity1, commodity1, commodity1]
    @test fusedBundle.orders[1].volume == 75
    @test fusedBundle.orders[1].bpUnits == Dict(
        :port_transport => 1, :delivery => 1, :direct => 1, :cross_plat => 1, :oversea => 1
    )
    @test fusedBundle.orders[1].minPackSize == 10
    @test fusedBundle.orders[1].stockCost == 18.0
    # Its second order comes from order 4
    @test fusedBundle.orders[2].bundleHash == UInt(0)
    @test fusedBundle.orders[2].deliveryDate == 2
    @test fusedBundle.orders[2].hash == hash(2, UInt(0))
    @test fusedBundle.orders[2].content == [commodity2, commodity1]
    @test fusedBundle.orders[2].volume == order44.volume
    @test fusedBundle.orders[2].bpUnits == Dict(
        :port_transport => 1, :delivery => 1, :direct => 1, :cross_plat => 1, :oversea => 1
    )
    @test fusedBundle.orders[2].minPackSize == order44.minPackSize
    @test fusedBundle.orders[2].stockCost == order44.stockCost
    # And thats all 
    @test length(fusedBundle.orders) == 2
end