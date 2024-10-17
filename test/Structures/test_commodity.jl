# Create an instance of Commodity
part_num = "A123"
size = 10
stock_cost = 2.5
commodity = OFOND.Commodity(UInt(0), hash(part_num), size, stock_cost)

# Test that Commodity is not mutable
@test !ismutable(commodity)

commodity2 = OFOND.Commodity(0, hash(part_num), size + 2, stock_cost - 1.0)

# Testing hash function
@testset "Hash" begin
    @test hash(commodity) == hash(hash(part_num), UInt(0))
    @test hash(commodity) == hash(commodity2)
end

# Test (in)equality and comparison
@testset "Equality and Comparison" begin
    @test commodity == commodity2
    @test commodity.size != commodity2.size
    commodity3 = OFOND.Commodity(1, hash("B456"), 5, 3.0)
    @test commodity != commodity3
    # Size comparison 
    @test commodity < commodity2
    @test commodity3 < commodity
end

# Testing show function 
@testset "Show" begin
    io = IOBuffer()
    show(io, commodity)
    content = String(take!(io))
    @test contains(content, "Commodity($(UInt(0)), $(hash(part_num)), $size, $stock_cost)")
end

# Testing zero function 
@testset "Zero" begin
    @test OFOND.zero(OFOND.Commodity) == OFOND.Commodity(UInt(0), UInt(0), 0, 0.0)
end
