# Unit tests for first fit decreasing
@testset "First Fit Decreasing" begin
    bins = OFOND.Bin[]
    newBins = OFOND.first_fit_decreasing!(bins, 10, OFOND.Commodity[])
    @test length(bins) == newBins == 0

    newBins = OFOND.first_fit_decreasing!(bins, 10, [commodity1, commodity1, commodity1])
    @test length(bins) == newBins == 3
    @test bins == fill(OFOND.Bin(0, 10, [commodity1]), 3)

    newBins = OFOND.first_fit_decreasing!(bins, 20, [commodity1, commodity1, commodity1])
    @test length(bins) == 5
    @test newBins == 2
    @test bins == [
        OFOND.Bin(0, 10, [commodity1]),
        OFOND.Bin(0, 10, [commodity1]),
        OFOND.Bin(0, 10, [commodity1]),
        OFOND.Bin(0, 20, [commodity1, commodity1]),
        OFOND.Bin(10, 10, [commodity1]),
    ]

    bins = [OFOND.Bin(7, 10, [commodity1])]
    newBins = OFOND.first_fit_decreasing!(bins, 20, [commodity1, commodity2, commodity3])
    @test length(bins) == 3
    @test newBins == 2
    @test bins == [
        OFOND.Bin(2, 15, [commodity1, commodity3]),
        OFOND.Bin(5, 15, [commodity2]),
        OFOND.Bin(10, 10, [commodity1]),
    ]

    bins = [OFOND.Bin(7, 10, [commodity1])]
    newBins = OFOND.first_fit_decreasing!(
        bins, 20, [commodity1, commodity2, commodity3]; sorted=true
    )
    @test length(bins) == 3
    @test newBins == 2
    @test bins == [
        OFOND.Bin(2, 15, [commodity1, commodity3]),
        OFOND.Bin(10, 10, [commodity1]),
        OFOND.Bin(5, 15, [commodity2]),
    ]
end

@testset "First Fit Decreasing (others)" begin
    # Returns a copy instead of modifying
    bins = OFOND.Bin[]
    newBins = OFOND.first_fit_decreasing(bins, 10, [commodity1, commodity1, commodity1])
    @test length(bins) == 0
    @test length(newBins) == 3
    @test newBins == fill(OFOND.Bin(0, 10, [commodity1]), 3)

    bins = [OFOND.Bin(7, 10, [commodity1])]
    newBins = OFOND.first_fit_decreasing(bins, 20, [commodity1, commodity2, commodity3])
    @test length(bins) == 1
    @test length(newBins) == 3
    @test newBins == [
        OFOND.Bin(2, 15, [commodity1, commodity3]),
        OFOND.Bin(5, 15, [commodity2]),
        OFOND.Bin(10, 10, [commodity1]),
    ]

    # Wrapper for objects
    bins = OFOND.Bin[]
    newBins1 = OFOND.first_fit_decreasing!(bins, supp1_to_plant, order2)
    newBins2 = OFOND.first_fit_decreasing!(bins, supp2_to_plant, order3)
    @test length(bins) == 2
    @test newBins1 == newBins2 == 1
    @test bins == [
        OFOND.Bin(5, 45, [commodity2, commodity2, commodity2]),
        OFOND.Bin(40, 10, [commodity1]),
    ]
end

@testset "Tentative FFD" begin
    CAPACITIES = Int[]

    bins = [OFOND.Bin(7, 10, [commodity1]), OFOND.Bin(2), OFOND.Bin(15)]
    @test OFOND.get_capacities(bins, CAPACITIES) == (3, 3)
    @test CAPACITIES == [7, 2, 15]

    OFOND.add_capacity(CAPACITIES, 4, 5)
    @test CAPACITIES == [7, 2, 15, 5]

    bins = [OFOND.Bin(7, 10, [commodity1])]
    @test OFOND.get_capacities(bins, CAPACITIES) == (1, 1)
    @test CAPACITIES == [7, -1, -1, -1]
    # Same tests as base FFD but also check that the bins are not modified
    newBins = OFOND.tentative_first_fit(
        bins, 20, [commodity1, commodity2, commodity3], CAPACITIES
    )
    @test newBins == 2
    @test bins == [OFOND.Bin(7, 10, [commodity1])]

    newBins1 = OFOND.tentative_first_fit(bins, supp1_to_plant, order2, CAPACITIES)
    @test newBins1 == 1
    @test bins == [OFOND.Bin(7, 10, [commodity1])]
end

@testset "Best Fit Decreasing" begin
    # get capa left 
    @test OFOND.best_fit_capacity(OFOND.Bin(11, 10, [commodity1]), commodity1) == 1
    @test OFOND.best_fit_capacity(OFOND.Bin(10, 10, [commodity1]), commodity1) == 0
    @test OFOND.best_fit_capacity(OFOND.Bin(9, 10, [commodity1]), commodity1) ==
        OFOND.INFINITY
    # packing algorithm
    bins = OFOND.Bin[]
    newBins = OFOND.best_fit_decreasing(bins, 10, [commodity1, commodity1, commodity1])
    @test length(bins) == 0
    @test length(newBins) == 3
    @test newBins == fill(OFOND.Bin(0, 10, [commodity1]), 3)

    newBins = OFOND.best_fit_decreasing!(bins, 10, [commodity1, commodity1, commodity1])
    @test length(bins) == newBins == 3
    @test bins == fill(OFOND.Bin(0, 10, [commodity1]), 3)

    bins = [OFOND.Bin(7, 10, [commodity1]), OFOND.Bin(20), OFOND.Bin(17), OFOND.Bin(18)]
    newBins = OFOND.best_fit_decreasing!(bins, 20, [commodity1, commodity2, commodity3])
    @test length(bins) == 4
    @test newBins == 0
    @test bins == [
        OFOND.Bin(2, 15, [commodity1, commodity3]),
        OFOND.Bin(20),
        OFOND.Bin(2, 15, [commodity2]),
        OFOND.Bin(8, 10, [commodity1]),
    ]
end

# FFD and BFD give three bins with different assignments, MILP gives two
commodity4 = OFOND.Commodity(0, hash("A123"), 4, 0.7)
commodity5 = OFOND.Commodity(0, hash("A123"), 3, 0.6)
commodity6 = OFOND.Commodity(0, hash("A123"), 2, 0.4)

@testset "MILP Packing" begin
    bins = OFOND.Bin[]
    newBins = OFOND.milp_packing(bins, 10, [commodity1, commodity1, commodity1])
    @test length(bins) == 0
    @test length(newBins) == 3
    @test newBins == fill(OFOND.Bin(0, 10, [commodity1]), 3)

    newBins = OFOND.milp_packing!(bins, 10, [commodity1, commodity1, commodity1])
    @test length(bins) == newBins == 3
    @test bins == fill(OFOND.Bin(0, 10, [commodity1]), 3)

    bins = OFOND.Bin[]
    coms = [
        commodity3, commodity4, commodity5, commodity6, commodity6, commodity6, commodity6
    ]
    newBins = OFOND.milp_packing!(bins, 10, coms)
    @test length(bins) == newBins == 2
    @test bins == [
        OFOND.Bin(0, 10, [commodity3, commodity5, commodity6]),
        OFOND.Bin(0, 10, [commodity4, commodity6, commodity6, commodity6]),
    ]

    bins = OFOND.Bin[]
    newBins = OFOND.first_fit_decreasing!(bins, 10, coms)
    @test length(bins) == newBins == 3
    nonOptBins = [
        OFOND.Bin(1, 9, [commodity3, commodity4]),
        OFOND.Bin(1, 9, [commodity5, commodity6, commodity6, commodity6]),
        OFOND.Bin(8, 2, [commodity6]),
    ]
    @test bins == nonOptBins

    bins = OFOND.Bin[]
    newBins = OFOND.best_fit_decreasing!(bins, 10, coms)
    @test length(bins) == newBins == 3
    @test bins == nonOptBins
end