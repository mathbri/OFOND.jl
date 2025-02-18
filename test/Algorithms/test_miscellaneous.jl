# Redefining instance to avoid bugs 
network = get_network()
commodity1, commodity2 = get_commodities()
order11, order22, order33, order44 = get_order_with_prop()
bundle11, bundle22, bundle33 = get_bundles_with_prop()
bundles = [bundle11, bundle22, bundle33]
TTGraph = OFOND.TravelTimeGraph(network, bundles)
TSGraph = OFOND.TimeSpaceGraph(network, 4)
dates = ["2024-01-01", "2024-01-02", "2024-01-03", "2024-01-04"]
partNumbers = Dict(hash("A123") => "A123", hash("B456") => "B456")
instance = OFOND.Instance(network, TTGraph, TSGraph, bundles, 4, dates, partNumbers)

supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]
supp2fromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]

supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
supp3Step3 = TSGraph.hashToIdx[hash(3, supplier3.hash)]
supp2Step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]

supp3Step4 = TSGraph.hashToIdx[hash(4, supplier3.hash)]
plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]

@testset "Shortest Delivery" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.shortest_delivery!(sol, instance)
    # all bundles have direct paths
    @test sol.bundlePaths == [
        [supp1FromDel2, plantFromDel0],
        [supp2fromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    # only the plant has bundle on nodes
    @test sol.bundlesOnNode[plantFromDel0] == [1, 2, 3]
    otherBundlesOnNode = filter(p -> p.first != plantFromDel0, sol.bundlesOnNode)
    @test all(p -> length(p.second) == 0, otherBundlesOnNode)
    # bins should be filled accordingly
    @test sol.bins[supp1Step3, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[supp2Step4, plantStep1] == [OFOND.Bin(21, 30, [commodity2, commodity2])]
    @test sol.bins[supp3Step3, plantStep1] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    @test sol.bins[supp3Step4, plantStep2] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    I, J, V = findnz(sol.bins)
    # test equivalent to : all other arcs don't have bins
    @test sum(x -> length(x), V) == 4
    @test OFOND.compute_cost(instance, sol) ≈ 89.9497737556561
end

xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]
supp2fromDel2 = TTGraph.hashToIdx[hash(2, supplier2.hash)]

@testset "Average Delivery" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.average_delivery!(sol, instance)
    # all bundles have lower bound paths
    @test sol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2fromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    filteredBundleOnNode = filter(p -> length(p.second) > 0, sol.bundlesOnNode)
    @test filteredBundleOnNode ==
        Dict(xdockFromDel1 => [1, 2, 3], plantFromDel0 => [1, 2, 3])
    # bundle 1 bins
    xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
    supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
    @test sol.bins[supp1Step3, xdockStep4] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[xdockStep4, plantStep1] == [
        OFOND.Bin(0, 50, [commodity1, commodity1, commodity2, commodity2]),
        OFOND.Bin(25, 25, [commodity2, commodity1]),
    ]
    # bundle 2 bins
    supp2Step3 = TSGraph.hashToIdx[hash(3, supplier2.hash)]
    @test sol.bins[supp2Step3, xdockStep4] == [OFOND.Bin(21, 30, [commodity2, commodity2])]
    # bundle 3 bins
    supp3Step3 = TSGraph.hashToIdx[hash(3, supplier3.hash)]
    @test sol.bins[supp3Step3, xdockStep4] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    supp3Step4 = TSGraph.hashToIdx[hash(4, supplier3.hash)]
    xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]
    @test sol.bins[supp3Step4, xdockStep1] == [OFOND.Bin(27, 25, [commodity2, commodity1])]
    plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]
    @test sol.bins[xdockStep1, plantStep2] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    filledArcs = count(x -> length(x) > 0, findnz(sol.bins)[3])
    @test filledArcs == 6
    @test OFOND.compute_cost(instance, sol) ≈ 70.79909502262444
end

@testset "Random Delivery" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    OFOND.random_delivery!(sol, instance; check=true)
    # Very little can be tested has its random 
    @test OFOND.is_feasible(instance, sol)
    println("Solution : $(sol.bundlePaths)")
    println("Cost = $(OFOND.compute_cost(instance, sol))")
end

supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]

@testset "Full MILP construction" begin
    # Pertubation construction 
    pert1 = OFOND.full_perturbation(instance)
    @test pert1.type == :arc_flow
    @test pert1.bundleIdxs == [1, 2, 3]
    @test pert1.src == 0
    @test pert1.dst == 0
    @test pert1.oldPaths == [
        [supp1FromDel2, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    @test pert1.newPaths == Vector{Int}[]
    @test pert1.loads == map(arc -> 0, TSGraph.networkArcs)
    # Testing model with packing 
    model = OFOND.full_lower_bound_milp(instance)
    @test num_variables(model) == 30
    @test length(model[:x][1, :]) == 7
    @test length(model[:x][2, :]) == 4
    @test length(model[:x][3, :]) == 7
    @test length(model[:tau]) == 12
    @test length(model[:path]) == 16
    @test length(model[:packing]) == 12
    # Testing model without packing
    model = OFOND.full_lower_bound_milp(instance; withPacking=false)
    @test num_variables(model) == 18
    @test length(model[:x][1, :]) == 7
    @test length(model[:x][2, :]) == 4
    @test length(model[:x][3, :]) == 7
    @test_throws KeyError model[:tau]
    @test length(model[:path]) == 16
    @test_throws KeyError model[:packing]
end

# How to check the correct problem is solved whithin the function ? Tests in lns_milp ensures it 
@testset "MILP Lower Bound" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    # Compute the lower bound of the instance 
    bound = OFOND.milp_lower_bound!(sol, instance)
    @test bound ≈ 70.79911502262443
    # Check the solution obtained 
    @test sol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2fromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    filledArcs = count(x -> length(x) > 0, findnz(sol.bins)[3])
    @test filledArcs == 6
    @test OFOND.compute_cost(instance, sol) ≈ 70.79909502262444
end

supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
supp3FromDel3 = TTGraph.hashToIdx[hash(3, supplier3.hash)]

@testset "MILP heuristics" begin
    # get a solution from each heuristic 
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    sol2, sol3 = deepcopy(sol), deepcopy(sol)
    OFOND.plant_by_plant_milp!(sol, instance)
    OFOND.customer_by_customer_milp!(sol2, instance)
    OFOND.random_by_random_milp!(sol3, instance)
    # should be all the same because MAX_MILP_VAR is huge compared to the tiny instance
    @test sol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2fromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    @test sol.bundlePaths == sol2.bundlePaths
    @test sol.bundlePaths == sol3.bundlePaths
    filledArcs = count(x -> length(x) > 0, findnz(sol.bins)[3])
    @test filledArcs == 6
    @test OFOND.compute_cost(instance, sol) ≈ 70.799095
end

@testset "Mix Greedy & LB" begin
    # get the three solutions obtained from this heuristic
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    gSol, lbSol = OFOND.mix_greedy_and_lower_bound!(sol, instance; check=true)
    # Paths
    @test sol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2fromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    @test sol.bundlePaths == gSol.bundlePaths
    @test sol.bundlePaths == lbSol.bundlePaths
    # Cost
    @test OFOND.compute_cost(instance, sol) ≈ 70.799095
    @test OFOND.compute_cost(instance, sol) ≈ OFOND.compute_cost(instance, gSol)
    @test OFOND.compute_cost(instance, sol) ≈ OFOND.compute_cost(instance, lbSol)
end

@testset "Fully outsourced solution" begin
    # Testing with default options
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    cost = OFOND.fully_outsourced!(sol, instance)
    @test sol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2fromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    @test cost ≈ 58.799125
    @test OFOND.compute_cost(instance, sol) ≈ 70.799095
    # Testing with max path length to 2
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    cost = OFOND.fully_outsourced!(sol, instance; maxPathLength=2)
    @test sol.bundlePaths == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2fromDel2, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    @test cost ≈ 58.799125
    @test OFOND.compute_cost(instance, sol) ≈ 70.799095
    # Testing with max path length to 1
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    cost = OFOND.fully_outsourced!(sol, instance; maxPathLength=1)
    @test sol.bundlePaths == [
        [supp1FromDel2, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    @test cost ≈ 129.949813
    @test OFOND.compute_cost(instance, sol) ≈ 89.949773
end