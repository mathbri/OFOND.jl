# using instance2 for more diversity
# Modifying instance a little for testing
# Adding a cycle in the network that won't be one in the time expansion
network2 = get_network()

bundle11, bundle22, bundle33 = get_bundles_with_prop()
bundles = [bundle11, bundle22, bundle33]

xdock2 = OFOND.NetworkNode("006", :xdock, "FR", "EU", true, 1.0)
xdock3 = OFOND.NetworkNode("007", :xdock, "CN", "AS", true, 1.0)
OFOND.add_node!(network2, xdock2)
OFOND.add_node!(network2, xdock3)

xdock1_to_2 = OFOND.NetworkArc(:cross_plat, 0.1, 1, true, 5.0, false, 0.0, 50)
xdock1_to_3 = OFOND.NetworkArc(:cross_plat, 0.1, 1, true, 4.0, false, 0.0, 50)
xdock2_to_3 = OFOND.NetworkArc(:cross_plat, 0.1, 0, true, 2.0, false, 0.0, 50)
xdock2_to_plant = OFOND.NetworkArc(:cross_plat, 0.1, 1, true, 6.0, false, 1.0, 50)
xdock3_to_plant = OFOND.NetworkArc(:cross_plat, 0.1, 1, true, 3.0, false, 1.0, 50)

OFOND.add_arc!(network2, xdock, xdock2, xdock1_to_2)
OFOND.add_arc!(network2, xdock, xdock3, xdock1_to_3)
OFOND.add_arc!(network2, xdock2, xdock3, xdock2_to_3)
OFOND.add_arc!(network2, xdock2, plant, xdock2_to_plant)
OFOND.add_arc!(network2, xdock3, plant, xdock3_to_plant)

# Cretaing new instance
TTGraph2 = OFOND.TravelTimeGraph(network2, bundles)
TSGraph2 = OFOND.TimeSpaceGraph(network2, 4)
instance2 = OFOND.Instance(network2, TTGraph2, TSGraph2, bundles, 4, dates, partNumbers)
instance2 = OFOND.add_properties(instance2, OFOND.tentative_first_fit, CAPACITIES)

sol = OFOND.Solution(instance2)

supp1FromDel3 = TTGraph2.hashToIdx[hash(3, supplier1.hash)]
supp3FromDel3 = TTGraph2.hashToIdx[hash(3, supplier3.hash)]
supp1FromDel2 = TTGraph2.hashToIdx[hash(2, supplier1.hash)]
supp3FromDel2 = TTGraph2.hashToIdx[hash(2, supplier3.hash)]
xdock1FromDel2 = TTGraph2.hashToIdx[hash(2, xdock.hash)]
xdock1FromDel1 = TTGraph2.hashToIdx[hash(1, xdock.hash)]
xdock2FromDel1 = TTGraph2.hashToIdx[hash(1, xdock2.hash)]
xdock3FromDel1 = TTGraph2.hashToIdx[hash(1, xdock3.hash)]
supp2FromDel1 = TTGraph2.hashToIdx[hash(1, supplier2.hash)]
plantFromDel0 = TTGraph2.hashToIdx[hash(0, plant.hash)]
supp2FromDel2 = TTGraph2.hashToIdx[hash(2, supplier2.hash)]
xdock3fromDel1 = TTGraph2.hashToIdx[hash(1, xdock3.hash)]

xdock3Step4 = TSGraph2.hashToIdx[hash(4, xdock3.hash)]
plantStep1 = TSGraph2.hashToIdx[hash(1, plant.hash)]
xdock2Step1 = TSGraph2.hashToIdx[hash(1, xdock2.hash)]
xdock1Step3 = TSGraph2.hashToIdx[hash(3, xdock.hash)]
xdock2Step4 = TSGraph2.hashToIdx[hash(4, xdock2.hash)]
plantStep2 = TSGraph2.hashToIdx[hash(2, plant.hash)]

oldPaths = [
    [supp1FromDel2, plantFromDel0],
    [supp2FromDel1, plantFromDel0],
    [supp3FromDel3, xdock1FromDel2, xdock2FromDel1, plantFromDel0],
]

# Updating costs with slope scaling
OFOND.slope_scaling_cost_update!(instance2, sol)

@testset "Solving lns milps" begin
    # Creating base solution
    sol2 = OFOND.Solution(instance2)
    OFOND.update_solution!(sol2, instance2, bundles, oldPaths)
    println("Base sol cost : $(OFOND.compute_cost(instance2, sol2))")

    # Solving single_plant milp
    pert = OFOND.get_perturbation(:single_plant, instance2, sol2)
    paths = OFOND.solve_lns_milp(instance2, pert; warmStart=false)
    @test paths[sortperm(pert.bundleIdxs)] == [
        [supp1FromDel3, xdock1FromDel2, xdock3fromDel1, plantFromDel0],
        [supp2FromDel2, xdock1FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
    ]
    # Doing the same with warm start and verbose
    paths = OFOND.solve_lns_milp(instance2, pert; verbose=true)
    @test paths[sortperm(pert.bundleIdxs)] == [
        [supp1FromDel3, xdock1FromDel2, xdock3fromDel1, plantFromDel0],
        [supp2FromDel2, xdock1FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
    ]

    # Changing arc costs by changing load matrix
    pert.loads[xdock1Step3, xdock2Step4] -= 50
    pert.loads[xdock2Step4, plantStep1] -= 50
    pert.loads[xdock2Step1, plantStep2] -= 50
    paths = OFOND.solve_lns_milp(instance2, pert; verbose=true)
    @test paths[sortperm(pert.bundleIdxs)] == [
        [supp1FromDel2, xdock1FromDel1, plantFromDel0],
        [supp2FromDel2, xdock1FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock2FromDel1, plantFromDel0],
    ]

    # Solving two node common milp (bundle 1 and 3)
    sol2 = OFOND.Solution(instance2)
    paths = [
        [supp1FromDel3, xdock1FromDel2, xdock2FromDel1, plantFromDel0],
        [supp2FromDel2, xdock1FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock2FromDel1, plantFromDel0],
    ]
    OFOND.update_solution!(sol2, instance2, bundles, paths)
    pert = OFOND.two_shared_node_perturbation(
        instance2, sol2, xdock1FromDel2, plantFromDel0
    )
    paths = OFOND.solve_lns_milp(instance2, pert; verbose=true)
    @test pert.bundleIdxs == [1, 3]
    @test paths == [
        [xdock1FromDel2, xdock3FromDel1, plantFromDel0],
        [xdock1FromDel2, xdock3FromDel1, plantFromDel0],
    ]

    # Solving path flow milp 
    pert = OFOND.path_flow_perturbation(instance2, sol2, xdock1FromDel1, plantFromDel0)
    paths = OFOND.solve_lns_milp(instance2, pert; verbose=true)
    @test paths == [
        [supp1FromDel2, xdock1FromDel1, plantFromDel0],
        [supp2FromDel2, xdock1FromDel1, plantFromDel0],
        [supp3FromDel2, xdock1FromDel1, plantFromDel0],
    ]
end

supp1Step2 = TSGraph2.hashToIdx[hash(2, supplier1.hash)]
xdockStep3 = TSGraph2.hashToIdx[hash(3, xdock.hash)]
xdockStep4 = TSGraph2.hashToIdx[hash(4, xdock.hash)]
supp1Step3 = TSGraph2.hashToIdx[hash(3, supplier1.hash)]
supp3Step3 = TSGraph2.hashToIdx[hash(3, supplier3.hash)]
supp3Step4 = TSGraph2.hashToIdx[hash(4, supplier3.hash)]
supp2Step3 = TSGraph2.hashToIdx[hash(3, supplier2.hash)]
supp3Step2 = TSGraph2.hashToIdx[hash(2, supplier3.hash)]
xdock3Step1 = TSGraph2.hashToIdx[hash(1, xdock3.hash)]

@testset "Perturbation" begin
    # Computing on an empty perturbation
    sol2 = OFOND.Solution(instance2)
    oldPaths2 = [
        [supp1FromDel2, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    OFOND.update_solution!(sol2, instance2, bundles, oldPaths2)
    improv, changed = OFOND.perturbate!(sol2, instance2, :two_shared_node; verbose=true)
    @test isapprox(improv, 0.0)
    @test changed == 0
    @test sol2.bundlePaths == [
        [supp1FromDel2, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]

    # Having the result being the same as the old paths 
    sol2 = OFOND.Solution(instance2)
    oldPaths2 = [
        [supp1FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
        [supp2FromDel2, xdock1FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
    ]
    OFOND.update_solution!(sol2, instance2, bundles, oldPaths2)
    improv, changed = OFOND.perturbate!(sol2, instance2, :single_plant; verbose=true)
    @test isapprox(improv, 0.0)
    @test changed == 0
    @test sol2.bundlePaths == [
        [supp1FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
        [supp2FromDel2, xdock1FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
    ]

    # Testing the filter
    # Having only one or two paths change for the three in the perturbation 
    sol2 = OFOND.Solution(instance2)
    oldPaths2 = [
        [supp1FromDel2, plantFromDel0],
        [supp2FromDel2, xdock1FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    OFOND.update_solution!(sol2, instance2, bundles, oldPaths2)
    improv, changed = OFOND.perturbate!(sol2, instance2, :single_plant; verbose=true)
    @test isapprox(improv, -22.7153846)
    @test changed == 2
    @test sol2.bundlePaths == [
        [supp1FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
        [supp2FromDel2, xdock1FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
    ]
    # Checking paths that changes are empty 
    @test sol2.bins[supp1Step3, plantStep1] == OFOND.Bin[]
    @test sol2.bins[supp3Step3, plantStep1] == OFOND.Bin[]
    @test sol2.bins[supp3Step4, plantStep2] == OFOND.Bin[]
    # Checking bundle 2 filling didn't change
    @test sol2.bins[supp2Step3, xdockStep4] == [OFOND.Bin(21, 30, [commodity2, commodity2])]
    @test sol2.bins[xdockStep4, plantStep1] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
    # Checking new paths have commodities
    @test sol2.bins[supp1Step2, xdockStep3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    sort!(sol2.bins[xdockStep3, xdock3Step4][1].content; by=c -> c.partNumHash)
    @test sol2.bins[xdockStep3, xdock3Step4] ==
        [OFOND.Bin(5, 45, [commodity2, commodity1, commodity1, commodity1])]
    sort!(sol2.bins[xdock3Step4, plantStep1][1].content; by=c -> c.partNumHash)
    @test sol2.bins[xdock3Step4, plantStep1] ==
        [OFOND.Bin(5, 45, [commodity2, commodity1, commodity1, commodity1])]
    @test sol2.bins[supp3Step2, xdockStep3] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    @test sol2.bins[supp3Step3, xdockStep4] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    @test sol2.bins[xdockStep4, xdock3Step1] ==
        [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol2.bins[xdock3Step1, plantStep2] ==
        [OFOND.Bin(25, 25, [commodity2, commodity1])]
end

@testset "LNS heuristic" begin
    sol = OFOND.Solution(instance2)
    OFOND.update_solution!(sol, instance2, bundles, oldPaths)
    OFOND.LNS!(
        sol, instance2; timeLimit=1, perturbTimeLimit=1, lsTimeLimit=1, lsStepTimeLimit=1
    )
    # Testing optimal solution found
    @test OFOND.compute_cost(instance2, sol) ≈ 63.899095
    @test sol.bundlePaths == [
        [supp1FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
        [supp2FromDel2, xdock1FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
    ]
end