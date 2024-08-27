# using instance2 for more diversity
# Modifying instance a little for testing
# Adding a cycle in the network that won't be one in the time expansion
network2 = deepcopy(network)

xdock2 = OFOND.NetworkNode("006", :xdock, "FR", "EU", true, 1.0)
xdock3 = OFOND.NetworkNode("007", :xdock, "CN", "AS", true, 1.0)
supplier3 = OFOND.NetworkNode("008", :supplier, "CN", "AS", false, 0.0)
OFOND.add_node!(network2, xdock2)
OFOND.add_node!(network2, xdock3)
OFOND.add_node!(network2, supplier3)

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
OFOND.add_arc!(network2, supplier3, xdock, supp_to_plat)

# Modifying bundle 3 to make it not equal anymore to bundle 1
bundle11 = OFOND.Bundle(supplier1, plant, [order1], 1, bunH1, 10, 3)
bunH3 = hash(supplier3, hash(plant))
order33 = OFOND.Order(
    bunH3, 1, [commodity2, commodity1], hash(1, bunH3), 25, bpDict, 10, 6.0
)
order44 = OFOND.Order(
    bunH3, 2, [commodity1, commodity2], hash(1, bunH3), 25, bpDict, 10, 6.0
)
bundle33 = OFOND.Bundle(supplier3, plant, [order33, order44], 3, bunH3, 15, 3)

# Cretaing new instance
bundles[[1, 3]] = [bundle11, bundle33]
TTGraph2 = OFOND.TravelTimeGraph(network2, bundles)
TSGraph2 = OFOND.TimeSpaceGraph(network2, 4)
instance2 = OFOND.Instance(network2, TTGraph2, TSGraph2, bundles, 4, dates, partNumbers)

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

xdock3Step4 = TSGraph2.hashToIdx[hash(4, xdock3.hash)]
plantStep1 = TSGraph2.hashToIdx[hash(1, plant.hash)]

oldPaths = [
    [supp1FromDel2, plantFromDel0],
    [supp2FromDel1, plantFromDel0],
    [supp3FromDel3, xdock1FromDel2, xdock2FromDel1, plantFromDel0],
]

# Updating costs with slope scaling
OFOND.slope_scaling_cost_update!(TSGraph2, sol)

@testset "Solving lns milps" begin
    # Computing lower bound to test milp values
    newSol = OFOND.Solution(instance2)
    OFOND.lower_bound!(newSol, instance2)
    println("Lower bound sol cost : $(OFOND.compute_cost(instance2, newSol))")
    # Creating relaxedSol
    OFOND.update_solution!(sol, instance2, bundles, oldPaths)
    relaxedSol = OFOND.RelaxedSolution(sol, instance2, bundles)
    OFOND.update_solution!(sol, instance2, bundles, oldPaths; remove=true)
    # Adding all bundles with the single plant neighborhood
    paths = OFOND.solve_lns_milp(
        instance2, sol, relaxedSol, :single_plant; warmStart=false, verbose=false
    )
    @test paths == [
        [supp1FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
    ]

    # Doing the same with a warm start
    paths = OFOND.solve_lns_milp(instance2, sol, relaxedSol, :single_plant; verbose=true)
    @test paths == [
        [supp1FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
    ]

    # Putting things on direct paths to change costs
    # TODO : put more commodities on common arcs to actually change costs and eventually paths
    # OFOND.update_solution!(sol, instance2, bundles, paths)
    # OFOND.slope_scaling_cost_update!(TSGraph2, sol)
    # paths = OFOND.solve_lns_milp(
    #     instance2, sol, :single_plant, bundles, oldPaths; warmStart=false, verbose=true
    # )
    # @test paths == [
    #     [supp1FromDel2, xdock1FromDel1, plantFromDel0],
    #     [supp2FromDel1, plantFromDel0],
    #     [supp1FromDel2, plantFromDel0],
    # ]

    # Upating sol with new paths 
    OFOND.update_solution!(sol, instance2, bundles, paths)
    relaxedSol = OFOND.RelaxedSolution(sol, instance2, [bundle11, bundle33])
    OFOND.update_solution!(sol, instance2, bundles, paths; remove=true)
    # Changing current cost so that proposed paths are better
    TSGraph2.currentCost[xdock3Step4, plantStep1] = 100
    # reducing bundle 1 and 3 on arc (xdock3FromDel1, plantFromDel0)
    paths = OFOND.solve_lns_milp(
        instance2,
        sol,
        relaxedSol,
        :reduce;
        src=xdock3FromDel1,
        dst=plantFromDel0,
        verbose=false,
    )
    @test paths == [
        [supp1FromDel2, xdock1FromDel1, plantFromDel0],
        [supp3FromDel2, xdock1FromDel1, plantFromDel0],
    ]

    # attracting bundle 1 and 3 on arc (xdock2FromDel1, plantFromDel0)
    paths = OFOND.solve_lns_milp(
        instance2,
        sol,
        relaxedSol,
        :attract;
        src=xdock2FromDel1,
        dst=plantFromDel0,
        verbose=false,
    )
    @test paths == [
        [supp1FromDel3, xdock1FromDel2, xdock2FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock2FromDel1, plantFromDel0],
    ]

    # Adding bundle1 and 3 with warm start on different paths with two_node
    relaxedSol.bundlePaths[1] = [xdock1FromDel2, xdock2FromDel1, plantFromDel0]
    relaxedSol.bundlePaths[2] = [xdock1FromDel2, xdock3FromDel1, plantFromDel0]
    paths = OFOND.solve_lns_milp(
        instance2,
        sol,
        relaxedSol,
        :two_shared_node;
        src=xdock1FromDel2,
        dst=plantFromDel0,
        verbose=false,
    )
    @test paths == [
        [xdock1FromDel2, xdock2FromDel1, plantFromDel0],
        [xdock1FromDel2, xdock2FromDel1, plantFromDel0],
    ]
end

supp1Step2 = TSGraph2.hashToIdx[hash(2, supplier1.hash)]
xdockStep3 = TSGraph2.hashToIdx[hash(3, xdock.hash)]
xdockStep4 = TSGraph2.hashToIdx[hash(4, xdock.hash)]

@testset "Perturbation" begin
    # Redifining things because julia doesn't understand its own scope
    sol = OFOND.Solution(instance2)
    OFOND.slope_scaling_cost_update!(TSGraph2, sol)
    OFOND.update_solution!(sol, instance2, bundles, oldPaths)
    copySol = deepcopy(sol)
    startCost = OFOND.compute_cost(instance2, sol)

    # Changing cost threshold to remove neighborhood computation
    costImprov, idxs, paths = OFOND.perturbate!(
        sol, instance2, :single_plant, startCost, 1e3
    )
    @test costImprov ≈ 0.92884
    @test idxs == Int[]
    @test paths == [Int[]]
    @test sol.bundlePaths == copySol.bundlePaths
    @test sol.bins == copySol.bins

    # Changing start cost remove neighborhood acceptance
    costImprov, idxs, paths = OFOND.perturbate!(sol, instance2, :single_plant, -3e3, 1e1)
    @test costImprov ≈ 0.0
    @test idxs == Int[]
    @test paths == [Int[]]
    @test sol.bundlePaths == copySol.bundlePaths
    OFOND.clean_empty_bins!(sol, instance2)
    @test sol.bins == copySol.bins

    # One single plant 
    costImprov, idxs, paths = OFOND.perturbate!(
        sol, instance2, :single_plant, startCost, 1e1
    )
    @test costImprov ≈ -20.392
    @test idxs == [1, 2, 3]
    @test paths == oldPaths
    @test sol.bundlePaths == [
        [supp1FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
    ]
    # Test bundle on nodes
    @test sol.bundlesOnNode[xdock1FromDel2] == [1, 3]
    @test sol.bundlesOnNode[xdock2FromDel1] == Int[]
    @test sol.bundlesOnNode[xdock3FromDel1] == [1, 3]
    @test sol.bundlesOnNode[plantFromDel0] == [1, 2, 3]
    # Test bins
    # Bundle 1
    @test sol.bins[supp1Step2, xdockStep3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    # Bundle 1 et 3
    @test sol.bins[xdockStep3, xdock3Step4] ==
        [OFOND.Bin(5, 45, [commodity1, commodity1, commodity2, commodity1])]
    @test sol.bins[xdock3Step4, plantStep1] ==
        [OFOND.Bin(5, 45, [commodity1, commodity1, commodity2, commodity1])]
    # Bundle 2
    @test sol.bins[supp2Step4, plantStep1] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
    # Bundle 3
    supp3Step2 = TSGraph2.hashToIdx[hash(2, supplier3.hash)]
    supp3Step3 = TSGraph2.hashToIdx[hash(3, supplier3.hash)]
    xdock3Step1 = TSGraph2.hashToIdx[hash(1, xdock3.hash)]
    @test sol.bins[supp3Step2, xdockStep3] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol.bins[supp3Step3, xdockStep4] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol.bins[xdockStep4, xdock3Step1] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol.bins[xdock3Step1, plantStep2] == [OFOND.Bin(25, 25, [commodity2, commodity1])]

    # Changing sol to have only one two node possibility
    sol2 = OFOND.Solution(instance2)
    OFOND.slope_scaling_cost_update!(TSGraph2, sol2)
    oldPaths2 = [
        [supp1FromDel2, xdock1FromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, xdock1FromDel1, plantFromDel0],
    ]
    OFOND.update_solution!(sol2, instance2, bundles, oldPaths2)
    # Computing perturbation (no improv but computation still)
    costImprov, idxs, paths = OFOND.perturbate!(
        sol2, instance2, :two_shared_node, startCost, 1e1; verbose=false
    )
    @test -1e-5 < costImprov < 1e-5
    @test idxs == [1, 3]
    @test paths == [
        [supp1FromDel2, xdock1FromDel1, plantFromDel0],
        [supp3FromDel2, xdock1FromDel1, plantFromDel0],
    ]
    @test sol2.bundlePaths == [
        [supp1FromDel2, xdock1FromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, xdock1FromDel1, plantFromDel0],
    ]
    supp1Step3 = TSGraph2.hashToIdx[hash(3, supplier1.hash)]
    supp3Step4 = TSGraph2.hashToIdx[hash(4, supplier3.hash)]
    xdockStep1 = TSGraph2.hashToIdx[hash(1, xdock.hash)]
    @test sol2.bins[supp1Step3, xdockStep4] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol2.bins[xdockStep4, plantStep1] ==
        [OFOND.Bin(5, 45, [commodity1, commodity1, commodity2, commodity1])]
    @test sol2.bins[supp2Step4, plantStep1] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
    @test sol2.bins[supp3Step3, xdockStep4] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol2.bins[supp3Step4, xdockStep1] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol2.bins[xdockStep1, plantStep2] == [OFOND.Bin(25, 25, [commodity2, commodity1])]

    # One attract 
    TSGraph2.currentCost[xdockStep4, plantStep1] = 100
    costImprov, idxs, paths = OFOND.perturbate!(
        sol2, instance2, :attract, startCost, 1e1; inTest=true
    )
    @test costImprov ≈ 0.414
    @test idxs == [1, 3]
    @test paths == [
        [supp1FromDel2, xdock1FromDel1, plantFromDel0],
        [supp3FromDel2, xdock1FromDel1, plantFromDel0],
    ]
    @test sol2.bundlePaths == [
        [supp1FromDel3, xdock1FromDel2, xdock2FromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock2FromDel1, plantFromDel0],
    ]

    # One reduce
    costImprov, idxs, paths = OFOND.perturbate!(
        sol2, instance2, :reduce, startCost, 1e1; inTest=true
    )
    @test costImprov ≈ -8.0
    @test idxs == [1, 3]
    @test paths == [
        [supp1FromDel3, xdock1FromDel2, xdock2FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock2FromDel1, plantFromDel0],
    ]
    @test sol2.bundlePaths == [
        [supp1FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
    ]
    @test sol2.bins[supp1Step2, xdockStep3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol2.bins[xdockStep3, xdock3Step4] ==
        [OFOND.Bin(5, 45, [commodity1, commodity1, commodity2, commodity1])]
    @test sol2.bins[xdock3Step4, plantStep1] ==
        [OFOND.Bin(5, 45, [commodity1, commodity1, commodity2, commodity1])]
    @test sol2.bins[supp2Step4, plantStep1] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
    @test sol2.bins[supp3Step2, xdockStep3] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol2.bins[supp3Step3, xdockStep4] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol2.bins[xdockStep4, xdock3Step1] ==
        [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol2.bins[xdock3Step1, plantStep2] ==
        [OFOND.Bin(25, 25, [commodity2, commodity1])]
end

@testset "LNS heuristic" begin
    sol = OFOND.Solution(instance2)
    OFOND.update_solution!(sol, instance2, bundles, oldPaths)
    OFOND.LNS!(sol, instance2; timeLimit=60)
    # Testing optimal solution found
    @test sol.bundlePaths == [
        [supp1FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel3, xdock1FromDel2, xdock3FromDel1, plantFromDel0],
    ]
end