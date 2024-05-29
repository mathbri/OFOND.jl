# xdock = OFOND.NetworkNode("004", :xdock, "XDock1", LLA(2, 1), "FR", "EU", true, 1.0)
# port_l = OFOND.NetworkNode("005", :port_l, "PortL1", LLA(3, 3), "FR", "EU", true, 0.0)
# supp_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 50)
# supp1_to_plant = OFOND.NetworkArc(:direct, 2.0, 2, false, 10.0, false, 1.0, 50)
# port_to_plant = OFOND.NetworkArc(:oversea, 1.0, 1, true, 4.0, false, 1.0, 50)
@testset "Compute new cost" begin
    @test OFOND.compute_new_cost(supp1_to_plant, port_l, 1, [commodity1]) ≈ 10 + 0.1 + 5
    @test OFOND.compute_new_cost(supp1_to_plant, port_l, 2, [commodity1]) ≈ 20 + 0.1 + 5
    @test OFOND.compute_new_cost(supp1_to_plant, port_l, 1, [commodity1, commodity2]) ≈
        10 + 0.25 + 12
    @test OFOND.compute_new_cost(supp1_to_plant, xdock, 1, [commodity1]) ≈ 10 + 0.2 + 5
    @test OFOND.compute_new_cost(port_to_plant, port_l, 1, [commodity1]) ≈ 4 + 0.1 + 2.5
    @test OFOND.compute_new_cost(port_to_plant, xdock, 2, [commodity1, commodity2]) ≈
        8 + 0.25 + 0.25 + 6.0
    @test OFOND.compute_new_cost(supp_to_plat, xdock, 2, [commodity1, commodity2]) ≈
        2 + 0 + 0.25 + 6.0
end

supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
TTPath = [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]

supp1Step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]
TSPath = [supp1Step2, xdockStep3, portStep4, plantStep1]

supp2Step2 = TSGraph.hashToIdx[hash(2, supplier2.hash)]
TSPath2 = [supp2Step2, xdockStep3, portStep4, plantStep1]

sol = OFOND.Solution(TTGraph, TSGraph, bundles)
@testset "Add order" begin
    costAdded = OFOND.add_order!(sol, TSGraph, TSPath, order1)
    # Testing order content added to bins on path
    @test sol.bins[supp1Step2, xdockStep3] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[xdockStep3, portStep4] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(30, 20, [commodity1, commodity1])]
    # Testing cost added
    @test costAdded == 25.0

    OFOND.add_order!(sol, TSGraph, TSPath2, order2)
    @test sol.bins[supp2Step2, xdockStep3] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
    @test sol.bins[xdockStep3, portStep4] ==
        [OFOND.Bin(0, 50, [commodity1, commodity1, commodity2, commodity2])]
    @test sol.bins[portStep4, plantStep1] ==
        [OFOND.Bin(0, 50, [commodity1, commodity1, commodity2, commodity2])]
    @test costAdded == 25.0
end

@testset "Remove order" begin
    # Adding another order and removing the first
    costRemoved = OFOND.remove_order!(sol, TSGraph, TSPath, order1)
    # Testing only the second remains
    @test sol.bins[supp1Step2, xdockStep3] == [OFOND.Bin(50)]
    @test sol.bins[supp2Step2, xdockStep3] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
    @test sol.bins[xdockStep3, portStep4] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(20, 30, [commodity2, commodity2])]
    # Testing cost added
    @test costRemoved == -17.0

    OFOND.remove_order!(sol, TSGraph, TSPath2, order2)
    @test sol.bins[supp1Step2, xdockStep3] == [OFOND.Bin(50)]
    @test sol.bins[supp2Step2, xdockStep3] == [OFOND.Bin(50)]
    @test sol.bins[xdockStep3, portStep4] == [OFOND.Bin(50)]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(50)]
end

supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
portStep1 = TSGraph.hashToIdx[hash(1, port_l.hash)]
plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]

@testset "Update bins" begin
    # Same with add / remove order but give the bundle and TTPath instead
    costAdded = OFOND.update_bins!(sol, TSGraph, TTGraph, bundle3, TTPath)
    # Testing that the result are supposed to be the same for order 3
    @test sol.bins[supp1Step2, xdockStep3] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol.bins[xdockStep3, portStep4] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol.bins[portStep4, plantStep1] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    # Testing everything is shifted of 1 time step for order 4
    @test sol.bins[supp1Step3, xdockStep4] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol.bins[xdockStep4, portStep1] == [OFOND.Bin(25, 25, [commodity2, commodity1])]
    @test sol.bins[portStep1, plantStep2] == [OFOND.Bin(25, 25, [commodity2, commodity1])]

    @test costAdded == 49.0
end