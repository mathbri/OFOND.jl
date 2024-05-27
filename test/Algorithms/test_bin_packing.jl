# Unit tests for first fit decreasing
@testset "First Fit Decreasing" begin
    bins = Bin[]
    newBins = first_fit_decreasing!(bins, 10, [commodity1, commodity1, commodity1])
    @test length(bins) == newBins == 3
    @test bins == fill(Bin(0, 10, [commodity1]), 3)

    newBins = first_fit_decreasing!(bins, 20, [commodity1, commodity1, commodity1])
    @test length(bins) == 5
    @test newBins == 2
    @test bins == [
        Bin(0, 10, [commodity1]),
        Bin(0, 10, [commodity1]),
        Bin(0, 10, [commodity1]),
        Bin(0, 20, [commodity1, commodity1]),
        Bin(10, 10, [commodity1]),
    ]

    bins = [Bin(7, 10, [commodity1])]
    newBins = first_fit_decreasing!(bins, 20, [commodity1, commodity2, commodity3])
    @test length(bins) == 3
    @test newBins == 2
    @test bins == [
        Bin(2, 15, [commodity1, commodity3]),
        Bin(5, 15, [commodity2]),
        Bin(10, 10, [commodity1]),
    ]

    bins = [Bin(7, 10, [commodity1])]
    newBins = first_fit_decreasing!(
        bins, 20, [commodity1, commodity2, commodity3]; sorted=true
    )
    @test length(bins) == 3
    @test newBins == 2
    @test bins == [
        Bin(2, 15, [commodity1, commodity3]),
        Bin(10, 10, [commodity1]),
        Bin(5, 15, [commodity2]),
    ]
end

@testset "First Fit Decreasing (others)" begin
    # Returns a copy instead of modifying
    bins = Bin[]
    newBins = first_fit_decreasing(bins, 10, [commodity1, commodity1, commodity1])
    @test length(bins) == 0
    @test length(newBins) == 3
    @test newBins == fill(Bin(0, 10, [commodity1]), 3)

    bins = [Bin(7, 10, [commodity1])]
    newBins = first_fit_decreasing(bins, 20, [commodity1, commodity2, commodity3])
    @test length(bins) == 1
    @test length(newBins) == 3
    @test newBins == [
        Bin(2, 15, [commodity1, commodity3]),
        Bin(5, 15, [commodity2]),
        Bin(10, 10, [commodity1]),
    ]

    # Wrapper for objects
    bins = Bin[]
    newBins1 = first_fit_decreasing!(bins, supp1_to_plant, order2)
    newBins2 = first_fit_decreasing!(bins, supp2_to_plant, order3)
    @test length(bins) == 2
    @test newBins1 == newBins2 == 1
    @test bins ==
        [Bin(5, 45, [commodity2, commodity2, commodity2]), Bin(40, 10, [commodity1])]
end

@testset "Tentative FFD" begin
    # Same tests as base FFD but also check that the bins are not modified
    bins = [Bin(7, 10, [commodity1])]
    newBins = tentative_first_fit(bins, 20, [commodity1, commodity2, commodity3])
    @test newBins == 2
    @test bins == [Bin(7, 10, [commodity1])]

    newBins1 = first_fit_decreasing!(bins, supp1_to_plant, order2)
    @test newBins1 == 1
    @test bins == [Bin(7, 10, [commodity1])]
end

@testset "Best Fit Decreasing" begin
    # get capa left 
    @test best_fit_capacity(Bin(11, 10, [commodity1]), commodity1) == 1
    @test best_fit_capacity(Bin(10, 10, [commodity1]), commodity1) == 0
    @test best_fit_capacity(Bin(9, 10, [commodity1]), commodity1) == INFINITY
    # packing algorithm
    bins = Bin[]
    newBins = best_fit_decreasing(bins, 10, [commodity1, commodity1, commodity1])
    @test length(bins) == 0
    @test length(newBins) == 3
    @test newBins == fill(Bin(0, 10, [commodity1]), 3)

    newBins = best_fit_decreasing!(bins, 10, [commodity1, commodity1, commodity1])
    @test length(bins) == newBins == 3
    @test bins == fill(Bin(0, 10, [commodity1]), 3)

    bins = [Bin(7, 10, [commodity1]), Bin(20), Bin(17), Bin(18)]
    newBins = best_fit_decreasing!(bins, 20, [commodity1, commodity2, commodity3])
    @test length(bins) == 4
    @test newBins == 0
    @test bins == [
        Bin(2, 15, [commodity1, commodity3]),
        Bin(20),
        Bin(2, 15, [commodity2]),
        Bin(8, 10, [commodity1]),
    ]
end

# FFD and BFD give three bins with different assignments, MILP gives two
commodity4 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 4, 0.7))
commodity5 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 3, 0.6))
commodity6 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 2, 0.4))

@testset "MILP Packing" begin
    bins = Bin[]
    newBins = milp_packing(bins, 10, [commodity1, commodity1, commodity1])
    @test length(bins) == 0
    @test length(newBins) == 3
    @test newBins == fill(Bin(0, 10, [commodity1]), 3)

    newBins = milp_packing!(bins, 10, [commodity1, commodity1, commodity1])
    @test length(bins) == newBins == 3
    @test bins == fill(Bin(0, 10, [commodity1]), 3)

    bins = Bin[]
    coms = [
        commodity3, commodity4, commodity5, commodity6, commodity6, commodity6, commodity6
    ]
    newBins = milp_packing!(bins, 10, coms)
    @test length(bins) == newBins == 2
    @test bins == [
        Bin(0, 10, [commodity3, commodity5, commodity6]),
        Bin(0, 10, [commodity4, commodity6, commodity6, commodity6]),
    ]

    bins = Bin[]
    newBins = first_fit_decreasing!(
        bins, 10, [commodity3, commodity4, commodity5, commodity6, commodity7]
    )
    @test length(bins) == newBins == 3
    @test bins == [
        Bin(1, 9, [commodity3, commodity4]),
        Bin(1, 9, [commodity5, commodity6, commodity6, commodity6]),
    ],
    Bin(8, 2, [commodity6])

    bins = Bin[]
    newBins = best_fit_decreasing!(
        bins, 10, [commodity3, commodity4, commodity5, commodity6, commodity7]
    )
    @test length(bins) == newBins == 3
    @test bins == [
        Bin(1, 9, [commodity3, commodity4]),
        Bin(1, 9, [commodity5, commodity6, commodity6, commodity6]),
    ],
    Bin(8, 2, [commodity6])
end