# Creating instances
commodity1 = OFOND.Commodity(1, 1, 5, 1.0)
commodity2 = OFOND.Commodity(2, 2, 5, 1.0)

# Testing constructors
@testset "Constructors" begin
    @test OFOND.Bin(10) == OFOND.Bin(10, 0, OFOND.Commodity[])
    @test OFOND.Bin(10, 0, [commodity1]) ==
        OFOND.Bin(10, 0, [OFOND.Commodity(1, 1, 5, 1.0)])
    @test_throws AssertionError OFOND.Bin(-1, 0, OFOND.Commodity[])
    @test_throws AssertionError OFOND.Bin(10, -1, OFOND.Commodity[])
    @test OFOND.Bin(10, commodity1) == OFOND.Bin(5, 5, [OFOND.Commodity(1, 1, 5, 1.0)])
    @test OFOND.Bin(4, commodity1) == OFOND.Bin(0, 4, [OFOND.Commodity(1, 1, 5, 1.0)])
end

# Testing equality operator
@testset "Equality" begin
    bin1 = OFOND.Bin(10, 0, OFOND.Commodity[])
    bin2 = OFOND.Bin(10, 0, OFOND.Commodity[])
    @test bin1 == bin2
    @test bin1.idx != bin2.idx
end

# Testing show function 
@testset "Show" begin
    io = IOBuffer()
    bin = OFOND.Bin(10, 0, [commodity1])
    show(io, bin)
    content = String(take!(io))
    @test contains(content, "Bin(10, 0, [Commodity($(UInt(1)), $(UInt(1)), 5, 1.0)])")
end

# Testing add! function
@testset "add!" begin
    bin = OFOND.Bin(10, 0, OFOND.Commodity[])
    @test OFOND.add!(bin, commodity1)
    @test bin.capacity == 5
    @test bin.load == 5
    @test bin.content == [commodity1]
    @test bin.content[1] === commodity1

    fullBin = OFOND.Bin(2, 0, OFOND.Commodity[])
    @test !OFOND.add!(fullBin, commodity1)
    @test fullBin.capacity == 2
    @test fullBin.load == 0
    @test fullBin.content == OFOND.Commodity[]

    bin = OFOND.Bin(10, 0, OFOND.Commodity[])
    @test OFOND.add!(bin, [commodity1, commodity2])
    @test bin.capacity == 0
    @test bin.load == 10
    @test bin.content == [commodity1, commodity2]
end

# Testing remove! function
@testset "remove!" begin
    bin = OFOND.Bin(10, 10, [commodity1, commodity2])
    @test OFOND.remove!(bin, commodity1)
    @test bin.capacity == 15
    @test bin.load == 5
    @test bin.content == [commodity2]

    bin = OFOND.Bin(10, 10, [commodity1, commodity2])
    @test OFOND.remove!(bin, OFOND.Commodity(1, 1, 5, 1.0))
    @test bin.capacity == 15
    @test bin.load == 5
    @test bin.content == [commodity2]

    bin = OFOND.Bin(10, 10, [commodity1, commodity1])
    @test OFOND.remove!(bin, commodity1)
    @test bin.capacity == 20
    @test bin.load == 0
    @test bin.content == OFOND.Commodity[]

    bin = OFOND.Bin(10, 10, [commodity1, commodity1])
    @test !OFOND.remove!(bin, commodity2)
    @test bin.capacity == 10
    @test bin.load == 10
    @test bin.content == [commodity1, commodity1]

    bin = OFOND.Bin(10, 10, [commodity1, commodity2])
    @test OFOND.remove!(bin, [OFOND.Commodity(1, 1, 5, 1.0), OFOND.Commodity(2, 2, 5, 1.0)])
    @test bin.capacity == 20
    @test bin.load == 0
    @test bin.content == OFOND.Commodity[]
end

# Testing get_all_commodities method
@testset "get_all_commodities" begin
    ALL_COMMODITIES = OFOND.Commodity[]
    # testing the filling of the array
    bin1 = OFOND.Bin(10, 2, [commodity1, commodity2, commodity1])
    bin2 = OFOND.Bin(10, 2, [commodity1, commodity1])
    bins = [bin1, bin2]
    allComs = OFOND.get_all_commodities(bins, ALL_COMMODITIES)
    @test ALL_COMMODITIES == [commodity1, commodity2, commodity1, commodity1, commodity1]
    @test allComs == [commodity1, commodity2, commodity1, commodity1, commodity1]
    @test typeof(allComs) <: SubArray
    # testing the modification of the array
    bin1 = OFOND.Bin(10, 2, [commodity1, commodity1])
    bin2 = OFOND.Bin(10, 2, [commodity2])
    bins = [bin1, bin2]
    allComs = OFOND.get_all_commodities(bins, ALL_COMMODITIES)
    @test allComs == [commodity1, commodity1, commodity2]
    @test ALL_COMMODITIES == [commodity1, commodity1, commodity2, commodity1, commodity1]
end

# testing stock cost function
@testset "stock_cost" begin
    bin = OFOND.Bin(10, 0, [commodity1, commodity2])
    @test OFOND.stock_cost(bin) == 2.0

    bin = OFOND.Bin(10, 0, OFOND.Commodity[])
    @test OFOND.stock_cost(bin) == 0.0
end

# Testing zero
@testset "Zero" begin
    @test OFOND.zero(Vector{OFOND.Bin}) == OFOND.Bin[]
end

# Testing custom deepcopy 
@testset "my_deepcopy" begin
    bins = [
        OFOND.Bin(5, 10, [commodity1, commodity2]),
        OFOND.Bin(11, 10, [commodity1, commodity2]),
    ]
    bins2 = OFOND.my_deepcopy(bins)
    @test bins2 == bins
    # modifying bin to check if deepcopy works
    OFOND.add!(bins[1], commodity1)
    @test bins2 != bins
end
