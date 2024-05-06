# Test that Commodity is mutable
@test ismutable(Commodity)

# Create an instance of Commodity
part_num = "A123"
size = 10
lead_time_cost = 2.5
commodity_data = CommodityData(part_num, size, lead_time_cost)
commodity = Commodity(0, hash(part_num), commodity_data)

# Test getters
@test part_number(commodity) == part_num
@test size(commodity) == size
@test lead_time_cost(commodity) == lead_time_cost

# Test equality
commodity2 = Commodity(0, hash(part_num), commodity_data)
@test commodity == commodity2

# Test inequality
commodity3 = Commodity(1, hash("B456"), CommodityData("B456", 5, 3.0))
@test commodity != commodity3
