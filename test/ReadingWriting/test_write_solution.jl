supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]
supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]

supp2step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]

supp1step2 = TSGraph.hashToIdx[hash(2, supplier1.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]

supp3Step3 = TSGraph.hashToIdx[hash(3, supplier3.hash)]
supp3Step4 = TSGraph.hashToIdx[hash(4, supplier3.hash)]
plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]

# make solution
solution = OFOND.Solution(TTGraph, TSGraph, bundles)
OFOND.update_solution!(
    solution,
    instance,
    bundles,
    [TTPath, [supp2FromDel1, plantFromDel0], [supp3FromDel2, plantFromDel0]],
)
push!(solution.bins[supp2step4, plantStep1], OFOND.Bin(5, 5, [commodity2]))

@testset "Helpers" begin
    # shipments ids
    @test OFOND.get_shipments_ids(
        solution, [supp2step4, plantStep1], supp2step4, 2, commodity2
    ) == [""]
    @test OFOND.get_shipments_ids(
        solution, [supp2step4, plantStep1], supp2step4, 1, commodity1
    ) == String[]
    @test OFOND.get_shipments_ids(
        solution, [supp2step4, plantStep1], supp2step4, 1, commodity2
    ) ==
        string.([
        solution.bins[supp2step4, plantStep1][1].idx,
        solution.bins[supp2step4, plantStep1][2].idx,
    ])
    # bundle finder
    @test OFOND.create_bundle_finder(instance) == Dict{UInt,Int}(
        order1.hash => 1, order2.hash => 2, order3.hash => 3, order4.hash => 3
    )
end

@testset "Network design writing" begin
    io = IOBuffer()
    OFOND.write_network_design(io, solution, instance)
    # test buffer content
    content = String(take!(io))
    # bundle 1 : 1 order, 1 commodity, 4 nodes, 1 bin 
    contentTest1 = [
        "1,001,006,A123,0.1,2,2024-01-01,001,1,2024-01-02,$(solution.bins[supp1step2, xdockStep3][1].idx)",
        "1,001,006,A123,0.1,2,2024-01-01,004,2,2024-01-03,$(solution.bins[xdockStep3, portStep4][1].idx)",
        "1,001,006,A123,0.1,2,2024-01-01,005,3,2024-01-04,$(solution.bins[portStep4, plantStep1][1].idx)",
        "1,001,006,A123,0.1,2,2024-01-01,006,4,2024-01-01,\n",
    ]
    @test contains(content, join(contentTest1, "\n"))
    # bundle 2 : 1 order, 1 commodity, 2 nodes, 2 bins
    contentTest2 = [
        "2,002,006,B456,0.15,2,2024-01-01,002,1,2024-01-04,$(solution.bins[supp2step4, plantStep1][1].idx)",
        "2,002,006,B456,0.15,2,2024-01-01,002,1,2024-01-04,$(solution.bins[supp2step4, plantStep1][2].idx)",
        "2,002,006,B456,0.15,2,2024-01-01,006,2,2024-01-01,\n",
    ]
    @test contains(content, join(contentTest2, "\n"))
    # bundle 3 : 2 order, 2 commodities, 2 nodes, 1 bin
    contentTest3 = [
        "3,003,006,B456,0.15,1,2024-01-01,003,1,2024-01-03,$(solution.bins[supp3Step3, plantStep1][1].idx)",
        "3,003,006,B456,0.15,1,2024-01-01,006,2,2024-01-01,",
        "3,003,006,A123,0.1,1,2024-01-01,003,1,2024-01-03,$(solution.bins[supp3Step3, plantStep1][1].idx)",
        "3,003,006,A123,0.1,1,2024-01-01,006,2,2024-01-01,\n",
    ]
    @test contains(content, join(contentTest3, "\n"))
    contentTest4 = [
        "4,003,006,B456,0.15,1,2024-01-02,003,1,2024-01-04,$(solution.bins[supp3Step4, plantStep2][1].idx)",
        "4,003,006,B456,0.15,1,2024-01-02,006,2,2024-01-02,",
        "4,003,006,A123,0.1,1,2024-01-02,003,1,2024-01-04,$(solution.bins[supp3Step4, plantStep2][1].idx)",
        "4,003,006,A123,0.1,1,2024-01-02,006,2,2024-01-02,\n",
    ]
end

@testset "Shipment info writing" begin
    io = IOBuffer()
    OFOND.write_shipment_info(io, solution, instance)
    # test buffer content
    content = String(take!(io))
    contentTest = [
        "$(solution.bins[supp1step2, xdockStep3][1].idx),001,004,2024-01-02,2024-01-03,outsource,0.2,1.6,0.0,0.4",
        "$(solution.bins[xdockStep3, portStep4][1].idx),004,005,2024-01-03,2024-01-04,cross_plat,0.2,4.0,0.0,0.0",
        "$(solution.bins[portStep4, plantStep1][1].idx),005,006,2024-01-04,2024-01-01,oversea,0.2,4.0,0.4,0.0",
        "$(solution.bins[supp2step4, plantStep1][1].idx),002,006,2024-01-04,2024-01-01,direct,0.3,10.0,$(30/51),0.0",
        "$(solution.bins[supp2step4, plantStep1][2].idx),002,006,2024-01-04,2024-01-01,direct,0.05,10.0,$(5/51),0.0",
        "$(solution.bins[supp3Step3, plantStep1][1].idx),003,006,2024-01-03,2024-01-01,direct,0.25,10.0,$(25/52),0.0",
        "$(solution.bins[supp3Step4, plantStep2][1].idx),003,006,2024-01-04,2024-01-02,direct,0.25,10.0,$(25/52),0.0\n",
    ]
    for contentLine in contentTest
        @test contains(content, contentLine)
    end
end

# Redefining commodities, instance and bundles to avoid errors
bunH1 = hash(supplier1, hash(plant))
bunH2 = hash(supplier2, hash(plant))
bunH3 = hash(supplier3, hash(plant))

commodity1 = OFOND.Commodity(hash(1, bunH1), hash("A123"), 10, 2.5)
commodity2 = OFOND.Commodity(hash(1, bunH2), hash("B456"), 15, 3.5)
commodity3 = OFOND.Commodity(hash(1, bunH3), hash("A123"), 10, 2.5)
commodity4 = OFOND.Commodity(hash(1, bunH3), hash("B456"), 15, 3.5)
commodity5 = OFOND.Commodity(hash(2, bunH3), hash("A123"), 10, 2.5)
commodity6 = OFOND.Commodity(hash(2, bunH3), hash("B456"), 15, 3.5)

order1 = OFOND.Order(bunH1, 1, [commodity1, commodity1])
order2 = OFOND.Order(bunH2, 1, [commodity2, commodity2])
order3 = OFOND.Order(bunH3, 1, [commodity3, commodity4])
order4 = OFOND.Order(bunH3, 2, [commodity5, commodity6])

bundle1 = OFOND.Bundle(supplier1, plant, [order1], 1, bunH1, 10, 2)
bundle2 = OFOND.Bundle(supplier2, plant, [order2], 2, bunH2, 15, 1)
bundle3 = OFOND.Bundle(supplier3, plant, [order3, order4], 3, bunH3, 10, 3)

instance.bundles[1:3] = [bundle1, bundle2, bundle3]

solution = OFOND.Solution(TTGraph, TSGraph, bundles)
OFOND.update_solution!(
    solution,
    instance,
    bundles,
    [TTPath, [supp2FromDel1, plantFromDel0], [supp3FromDel2, plantFromDel0]],
)
push!(solution.bins[supp2step4, plantStep1], OFOND.Bin(5, 5, [commodity2]))

@testset "Shipment content writing" begin
    io = IOBuffer()
    # error : com.orderHash and order.hash don't match !
    OFOND.write_shipment_content(io, solution, instance)
    # test buffer content
    content = String(take!(io))
    contentTest = [
        "$(solution.bins[supp1step2, xdockStep3][1].idx),A123,001,006,2,0.1,0.2",
        "$(solution.bins[xdockStep3, portStep4][1].idx),A123,001,006,2,0.1,0.2",
        "$(solution.bins[portStep4, plantStep1][1].idx),A123,001,006,2,0.1,0.2",
        "$(solution.bins[supp2step4, plantStep1][1].idx),B456,002,006,2,0.15,0.3",
        "$(solution.bins[supp2step4, plantStep1][2].idx),B456,002,006,1,0.15,0.15",
        "$(solution.bins[supp3Step3, plantStep1][1].idx),B456,003,006,1,0.15,0.15",
        "$(solution.bins[supp3Step3, plantStep1][1].idx),A123,003,006,1,0.1,0.1",
        "$(solution.bins[supp3Step4, plantStep2][1].idx),B456,003,006,1,0.15,0.15",
        "$(solution.bins[supp3Step4, plantStep2][1].idx),A123,003,006,1,0.1,0.1",
    ]
    for contentLine in contentTest
        @test contains(content, contentLine)
    end
end

@testset "Write solution" begin
    OFOND.write_solution(solution, instance; suffix="test", directory=@__DIR__)
    # test file existence
    @test isfile("ReadingWriting\\network_design_test.csv")
    @test isfile("ReadingWriting\\shipment_info_test.csv")
    @test isfile("ReadingWriting\\shipment_content_test.csv")
end