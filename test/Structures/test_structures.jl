# Commodity
@testset "Commodity" begin
    include("test_commodity.jl")
end
# Order
@testset "Order" begin
    include("test_order.jl")
end
# Bundle
@testset "Bundle" begin
    include("test_bundle.jl")
end

# Bin
@testset "Bin" begin
    include("test_bin.jl")
end

# Network
@testset "Network" begin
    include("test_network.jl")
end
# Travel Time
@testset "TravelTime" begin
    include("test_travel_time.jl")
end
# Time Space 
@testset "TimeSpace" begin
    include("test_time_space.jl")
end
# Projectors
@testset "Projectors" begin
    include("test_projectors.jl")
end

# Struct utils
@testset "Struct utils" begin
    include("test_struct_utils.jl")
end
# Instance
@testset "Instance" begin
    include("test_instance.jl")
end
# Solution
@testset "Solution" begin
    include("test_solution.jl")
end