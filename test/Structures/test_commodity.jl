# Create an instance of Commodity
part_num = "A123"
size = 10
lead_time_cost = 2.5
commodity_data = OFOND.CommodityData(part_num, size, lead_time_cost)
commodity = OFOND.Commodity(0, hash(part_num), commodity_data)

# Test that Commodity is not mutable
@test !ismutable(commodity_data)
@test !ismutable(commodity)

# Test getters
@testset "getters" begin
    @test OFOND.part_number(commodity) == part_num
    @test OFOND.size(commodity) == size
    @test OFOND.lead_time_cost(commodity) == lead_time_cost
end

commodity2 = OFOND.Commodity(0, hash(part_num), commodity_data)

# Test (in)equality
@testset "equality" begin
    @test commodity == commodity2
    commodity3 = OFOND.Commodity(1, hash("B456"), OFOND.CommodityData("B456", 5, 3.0))
    @test commodity != commodity3
end

# Test memory affectation
@testset "memory affectation" begin
    # Commodity1 and Commodity2 are different objects 
    commodity1 = OFOND.Commodity(2, hash("C789"), commodity_data)
    @test commodity1 !== commodity2
    # But that the data in both is the same
    @test commodity.data === commodity2.data
end