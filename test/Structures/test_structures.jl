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

# Define nodes, arcs and network
supplier1, supplier2, supplier3, xdock, port_l, plant = get_nodes()
supp1_to_plat, supp2_to_plat, supp3_to_plat, supp1_to_plant, supp2_to_plant, supp3_to_plant, plat_to_plant, xdock_to_port, port_to_plant = get_arcs()
network = get_network()
# Define commodities, orders and bundles
commodity1, commodity2 = get_commodities()
order1, order2, order3, order4 = get_order()
bundle1, bundle2, bundle3 = get_bundles()
bundles = [bundle1, bundle2, bundle3]

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

# Redefining order3 to reove changes made over it 
bunH3 = hash(supplier3, hash(plant))
order3 = OFOND.Order(bunH3, 1, [commodity1, commodity2])

# Adding orders with properties
order11, order22, order33, order44 = get_order_with_prop()
bundle11, bundle22, bundle33 = get_bundles_with_prop()
bundles = [bundle11, bundle22, bundle33]
bundlesNP = [bundle1, bundle2, bundle3]

# Instance
@testset "Instance" begin
    include("test_instance.jl")
end
# Solution
@testset "Solution" begin
    include("test_solution.jl")
end
# Relaxed Solution
@testset "Perturbation" begin
    include("test_perturbation.jl")
end