# Creating instances
comData = OFOND.CommodityData("1", 5, 1)
commodity1 = OFOND.Commodity(1, 1, comData)
commodity2 = OFOND.Commodity(2, 2, comData)

@testset "Testing constructors" begin
    @test OFOND.Bin(10) == OFOND.Bin(10, 0, OFOND.Commodity[])
    @test OFOND.Bin(10, 0, [commodity1]) ==
        OFOND.Bin(10, 0, [OFOND.Commodity(1, 1, comData)])
    @test_throws AssertionError OFOND.Bin(-1, 0, OFOND.Commodity[])
    @test_throws AssertionError OFOND.Bin(10, -1, OFOND.Commodity[])
    @test OFOND.Bin(10, commodity1) == OFOND.Bin(5, 5, [OFOND.Commodity(1, 1, comData)])
    @test OFOND.Bin(4, commodity1) == OFOND.Bin(0, 4, [OFOND.Commodity(1, 1, comData)])
end

@testset "Testing add!" begin
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
end

@testset "Testing remove!" begin
    bin = OFOND.Bin(10, 10, [commodity1, commodity2])
    @test OFOND.remove!(bin, commodity1)
    @test bin.capacity == 15
    @test bin.load == 5
    @test bin.content == [commodity2]

    bin = OFOND.Bin(10, 10, [commodity1, commodity2])
    @test OFOND.remove!(bin, OFOND.Commodity(1, 1, comData))
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
    @test OFOND.remove!(
        bin, [OFOND.Commodity(1, 1, comData), OFOND.Commodity(2, 2, comData)]
    )
    @test bin.capacity == 20
    @test bin.load == 0
    @test bin.content == OFOND.Commodity[]
end

@testset "Testing get_all_commodities" begin
    bin1 = OFOND.Bin(10, 2, [commodity1, commodity2])
    bin2 = OFOND.Bin(10, 2, [commodity1])
    bins = [bin1, bin2]
    @test OFOND.get_all_commodities(bins) == [commodity1, commodity2, commodity1]
end

@testset "Testing zero" begin
    @test OFOND.zero(Vector{OFOND.Bin}) == OFOND.Bin[]
end
