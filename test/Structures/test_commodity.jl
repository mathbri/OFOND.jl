# Create an instance of Commodity
part_num = "A123"
size = 10
stock_cost = 2.5
commodity = OFOND.Commodity(0, hash(part_num), size, stock_cost)

# Test that Commodity is not mutable
@test !ismutable(commodity)

commodity2 = OFOND.Commodity(0, hash(part_num), size, stock_cost)

# Test (in)equality
@testset "equality" begin
    @test commodity == commodity2
    commodity3 = OFOND.Commodity(1, hash("B456"), 5, 3.0)
    @test commodity != commodity3
end
