plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
supp2FromDel2 = TTGraph.hashToIdx[hash(2, supplier2.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]

supp2step3 = TSGraph.hashToIdx[hash(3, supplier2.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]
supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
supp1Step4 = TSGraph.hashToIdx[hash(4, supplier1.hash)]
xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]
plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]

# make solution
solution = OFOND.Solution()
OFOND.update_solution!(
    solution,
    instance,
    bundles,
    [[supp2FromDel2, plantFromDel0], [supp1FromDel2, xdockFromDel1, plantFromDel0]],
)
push!(solution.bins[supp2step3, plantStep1], OFOND.Bin(5, 5, [commodity1]))

@testset "Helpers" begin
    # shipments ids
    @test OFOND.shipment_ids(
        solution, [supp2step3, plantStep1], supp2step3, 2, commodity1
    ) == [""]
    @test OFOND.shipment_ids(
        solution, [supp2step3, plantStep1], supp2step3, 1, commodity1
    ) ==
        string.([
        solution.bins[supp2step3, plantStep1][1].id,
        solution.bins[supp2step3, plantStep1][2].id,
    ])
    # find bundle
    @test OFOND.find_bundle(instance, commodity1) == bundle1
    @test OFOND.find_bundle(instance, commodity4) == bundle2
    @test OFOND.find_bundle(instance, commodity2) == bundle2
end

@testset "Line writers" begin
    io = IOBuffer()
    OFOND.write_network_design(io, solution, instance)
    # test buffer content
    content = String(take!(io))
    contentTest = [
        "1,002,003,B456,15,2,2024-01-01,002,1,2024-01-03,$(solution.bins[supp2step3, plantStep1][1].id)",
        "1,002,003,B456,15,2,2024-01-01,002,1,2024-01-03,$(solution.bins[supp2step3, plantStep1][2].id)",
        "1,002,003,B456,15,2,2024-01-01,003,2,2024-01-01,",
        "2,001,003,A123,10,1,2024-01-01,001,1,2024-01-03,$(solution.bins[supp1step3, xdockStep4][1].id)",
        "2,001,003,A123,10,1,2024-01-01,004,2,2024-01-04,$(solution.bins[xdockStep4, plantStep1][1].id)",
        "2,001,003,A123,10,1,2024-01-01,001,3,2024-01-01,",
        "2,001,003,B456,15,2,2024-01-01,001,1,2024-01-03,$(solution.bins[supp1step3, xdockStep4][1].id)",
        "2,001,003,B456,15,2,2024-01-01,001,2,2024-01-04,$(solution.bins[xdockStep4, plantStep1][1].id)",
        "2,001,003,B456,15,2,2024-01-01,001,3,2024-01-01,",
        "3,001,003,A123,10,1,2024-01-02,001,1,2024-01-04,$(solution.bins[supp1step4, xdockStep1][1].id)",
        "3,001,003,A123,10,1,2024-01-02,004,2,2024-01-01,$(solution.bins[xdockStep1, plantStep2][1].id)",
        "3,001,003,A123,10,1,2024-01-02,001,3,2024-01-02,",
        "3,001,003,B456,15,2,2024-01-02,001,1,2024-01-04,$(solution.bins[supp1step4, xdockStep1][1].id)",
        "3,001,003,B456,15,2,2024-01-02,001,2,2024-01-01,$(solution.bins[xdockStep1, plantStep2][1].id)",
        "3,001,003,B456,15,2,2024-01-02,001,3,2024-01-02,",
    ]
    @test content == join(contentTest, "\n")

    io = IOBuffer()
    OFOND.write_shipment_info(io, solution, instance)
    # test buffer content
    content = String(take!(io))
    contentTest = [
        "$(solution.bins[supp2step3, plantStep1][1].id),002,003,2024-01-03,2024-01-01,direct,30,10,0.6,0.6",
        "$(solution.bins[supp2step3, plantStep1][2].id),002,003,2024-01-03,2024-01-01,direct,5,10,0.06,0.06",
        "$(solution.bins[supp1step3, xdockStep4][1].id),001,003,2024-01-03,2024-01-04,outsource,25,10,0.5,0.5",
        "$(solution.bins[xdockStep4, plantStep1][1].id),001,003,2024-01-04,2024-01-01,delivery,25,10,0.5,0.5",
        "$(solution.bins[supp1step4, xdockStep1][1].id),001,003,2024-01-04,2024-01-01,outsource,25,10,0.5,0.5",
        "$(solution.bins[xdockStep1, plantStep2][1].id),001,003,2024-01-01,2024-01-02,delivery,25,10,0.5,0.5",
    ]
    @test content == join(contentTest, "\n")

    io = IOBuffer()
    OFOND.write_shipment_content(io, solution, instance)
    # test buffer content
    content = String(take!(io))
    contentTest = [
        "1,$(solution.bins[supp2step3, plantStep1][1].id),B456,002,003,2,15,30",
        "2,$(solution.bins[supp2step3, plantStep1][2].id),B456,002,003,1,15,15",
        "3,$(solution.bins[supp1step3, xdockStep4][1].id),A123,001,003,1,10,10",
        "4,$(solution.bins[supp1step3, xdockStep4][1].id),B456,001,003,1,15,15",
        "5,$(solution.bins[xdockStep4, plantStep1][1].id),A123,001,003,1,10,10",
        "6,$(solution.bins[xdockStep4, plantStep1][1].id),B456,001,003,1,15,15",
        "7,$(solution.bins[supp1step4, xdockStep1][1].id),A123,001,003,1,10,10",
        "8,$(solution.bins[supp1step4, xdockStep1][1].id),B456,001,003,1,15,15",
        "9,$(solution.bins[xdockStep1, plantStep2][1].id),A123,001,003,1,10,10",
        "10,$(solution.bins[xdockStep1, plantStep2][1].id),B456,001,003,1,15,15",
    ]
    @test content == join(contentTest, "\n")
end

@testset "Write solution" begin
    OFOND.write_solution(solution, instance; suffix="test")
    # test file existence
    @test isfile("network_design_test.csv")
    @test isfile("shipment_info_test.csv")
    @test isfile("shipment_content_test.csv")
end