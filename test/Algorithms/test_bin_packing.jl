# Creating bin packing instances to test functions
capa = 10
sizes1 = [2, 2, 2, 3, 5, 6]
sizes2 = [2, 2, 2, 3, 5, 6, 6, 3, 3, 2, 2, 1, 3]

# Cretaing commodities related to it
commodities1 = [
    OFOND.Commodity(i, hash("A$(i)"), size, 1.0) for (i, size) in enumerate(sizes1)
]
commodities2 = [
    OFOND.Commodity(i, hash("A$(i)"), size, 1.0) for (i, size) in enumerate(sizes2)
]

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

    bins = [OFOND.Bin(10, 0, OFOND.Commodity[])]
    newBins = OFOND.first_fit_decreasing!(bins, 10, commodities1)
    @test length(bins) == 3
    @test newBins == 2
    @test bins == [
        OFOND.Bin(1, 9, commodities1[[6, 4]]),
        OFOND.Bin(1, 9, commodities1[[5, 1, 2]]),
        OFOND.Bin(8, 2, commodities1[[3]]),
    ]

    bins = OFOND.Bin[]
    newBins = OFOND.first_fit_decreasing!(bins, 10, commodities1; sorted=true)
    @test length(bins) == 3
    @test newBins == 3
    @test bins == [
        OFOND.Bin(1, 9, commodities1[1:4]),
        OFOND.Bin(5, 5, commodities1[[5]]),
        OFOND.Bin(4, 6, commodities1[[6]]),
    ]

    bins = [OFOND.Bin(10, 0, OFOND.Commodity[])]
    newBins = OFOND.first_fit_decreasing!(bins, 10, commodities2)
    @test length(bins) == 5
    @test newBins == 4
    @test bins == [
        OFOND.Bin(0, 10, commodities2[[6, 4, 12]]),
        OFOND.Bin(1, 9, commodities2[[7, 8]]),
        OFOND.Bin(0, 10, commodities2[[5, 9, 1]]),
        OFOND.Bin(1, 9, commodities2[[13, 2, 3, 10]]),
        OFOND.Bin(8, 2, commodities2[[11]]),
    ]
end

commodity3 = OFOND.Commodity(2, hash("C789"), 5, 0.5)

@testset "First Fit Decreasing (others)" begin
    # SubArray specialized function
    bins = OFOND.Bin[]
    newBins = OFOND.first_fit_decreasing!(bins, 10, view(commodities2, 1:6))
    @test length(bins) == 3
    @test newBins == 3
    @test bins == [
        OFOND.Bin(1, 9, commodities1[[6, 4]]),
        OFOND.Bin(1, 9, commodities1[[5, 1, 2]]),
        OFOND.Bin(8, 2, commodities1[[3]]),
    ]

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
        OFOND.Bin(41, 10, [commodity1]),
    ]
end

@testset "Tentative FFD" begin
    CAPACITIES = Int[]
    # Adding capacities from an empty vector
    bins = [OFOND.Bin(7, 10, [commodity1]), OFOND.Bin(2), OFOND.Bin(15)]
    @test OFOND.get_capacities(bins, CAPACITIES) == (3, 3)
    @test CAPACITIES == [7, 2, 15]
    # Adding a new capacity
    OFOND.add_capacity(CAPACITIES, 4, 5)
    @test CAPACITIES == [7, 2, 15, 5]
    # Finding the first bin (size = 8 and max idx = 4 for example)
    @test OFOND.findfirstbin(CAPACITIES, 8, 4) == 3
    @test OFOND.findfirstbin(CAPACITIES, 8, 2) == -1
    @test OFOND.findfirstbin(CAPACITIES, 16, 4) == -1

    # Adding capacities from a non-empty vector
    bins = [OFOND.Bin(7, 10, [commodity1])]
    @test OFOND.get_capacities(bins, CAPACITIES) == (1, 1)
    @test CAPACITIES == [7, -1, -1, -1]

    # Same tests as base FFD but also check that the bins are not modified
    newBins = OFOND.tentative_first_fit(
        bins, 20, [commodity1, commodity2, commodity3], CAPACITIES
    )
    @test newBins == 2
    @test bins == [OFOND.Bin(7, 10, [commodity1])]

    newBins = OFOND.tentative_first_fit(bins, supp1_to_plant, order2, CAPACITIES)
    @test newBins == 1
    @test bins == [OFOND.Bin(7, 10, [commodity1])]

    bins = OFOND.Bin[]
    newBins = OFOND.tentative_first_fit(bins, 10, commodities1, CAPACITIES)
    @test newBins == 3
    @test bins == OFOND.Bin[]
    @test CAPACITIES == [1, 1, 8, -1]
    newBins = OFOND.tentative_first_fit(bins, 10, commodities2, CAPACITIES)
    @test newBins == 5
    @test bins == OFOND.Bin[]
    @test CAPACITIES == [0, 1, 0, 1, 8]
end

@testset "Tentative FFD 2" begin
    CAPACITIES = [7, 2, 15, 5]
    # Finding the first bin (size = 5, cap = 0, start idx = 1, max idx = 4)
    @test OFOND.findfirstbin2(CAPACITIES, 5, 0, 1, 4) == (1, 0)
    # (size = 8, cap = 0, start idx = 1, max idx = 4)
    @test OFOND.findfirstbin2(CAPACITIES, 8, 0, 1, 4) == (3, 7)
    CAPACITIES = [7, 2, 7, 5, 8, 9]
    # (size = 8, cap = 7, start idx = 3, max idx = 4)
    @test OFOND.findfirstbin2(CAPACITIES, 8, 7, 2, 4) == (-1, 7)
    @test OFOND.findfirstbin2(CAPACITIES, 8, 7, 3, 6) == (5, 7)

    # Checking computations
    bins = OFOND.Bin[]
    newBins = OFOND.tentative_first_fit2(bins, 10, OFOND.Commodity[], CAPACITIES)
    @test newBins == 0
    @test bins == OFOND.Bin[]
    @test CAPACITIES == [-1, -1, -1, -1, -1, -1]

    newBins = OFOND.tentative_first_fit2(
        bins, 10, [commodity1, commodity1, commodity1], CAPACITIES
    )
    @test newBins == 3
    @test bins == OFOND.Bin[]
    @test CAPACITIES == [0, 0, 0, -1, -1, -1]

    newBins = OFOND.tentative_first_fit2(
        bins, 20, [commodity1, commodity1, commodity1], CAPACITIES
    )
    @test newBins == 2
    @test bins == OFOND.Bin[]
    @test CAPACITIES == [0, 10, -1, -1, -1, -1]

    newBins = OFOND.tentative_first_fit2(bins, 10, commodities1, CAPACITIES)
    @test newBins == 3
    @test bins == OFOND.Bin[]
    @test CAPACITIES == [1, 1, 8, -1, -1, -1]

    newBins = OFOND.tentative_first_fit2(bins, 10, commodities1, CAPACITIES; sorted=true)
    @test newBins == 3
    @test bins == OFOND.Bin[]
    @test CAPACITIES == [1, 5, 4, -1, -1, -1]

    newBins = OFOND.tentative_first_fit2(bins, 10, commodities2, CAPACITIES)
    @test newBins == 5
    @test bins == OFOND.Bin[]
    @test CAPACITIES == [0, 1, 0, 1, 8, -1]
end

@testset "Best Fit Decreasing" begin
    # get capa left 
    @test OFOND.best_fit_capacity(OFOND.Bin(11, 10, [commodity1]), commodity1) == 1
    @test OFOND.best_fit_capacity(OFOND.Bin(10, 10, [commodity1]), commodity1) == 0
    @test OFOND.best_fit_capacity(OFOND.Bin(9, 10, [commodity1]), commodity1) == 1_000_000

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

    # Tentative packing algorithm 
    CAPACITIES = [1, 2, 3, 4]
    bins = [OFOND.Bin(7, 10, [commodity1]), OFOND.Bin(20), OFOND.Bin(17), OFOND.Bin(18)]
    newBins = OFOND.tentative_best_fit(
        bins, 20, view([commodity1, commodity2, commodity3], 1:3), CAPACITIES
    )
    @test bins ==
        [OFOND.Bin(7, 10, [commodity1]), OFOND.Bin(20), OFOND.Bin(17), OFOND.Bin(18)]
    @test newBins == 0
    @test CAPACITIES == [2, 20, 2, 8]

    bins = [OFOND.Bin(10)]
    newBins = OFOND.tentative_best_fit(bins, 10, view(commodities1, 1:6), CAPACITIES)
    @test newBins == 2
    @test bins == [OFOND.Bin(10)]
    @test CAPACITIES == [1, 1, 8, -1]

    newBins = OFOND.tentative_best_fit(bins, 10, view(commodities2, 1:13), CAPACITIES)
    @test newBins == 4
    @test bins == [OFOND.Bin(10)]
    @test CAPACITIES == [0, 1, 0, 1, 8]
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