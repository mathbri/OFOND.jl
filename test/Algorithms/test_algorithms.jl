# Define nodes, arcs and network
networkNodes = get_nodes()
supplier1, supplier2, supplier3, xdock, port_l, plant = networkNodes
supp1_to_plat, supp2_to_plat, supp3_to_plat, supp1_to_plant, supp2_to_plant, supp3_to_plant, plat_to_plant, xdock_to_port, port_to_plant = get_arcs()
network = get_network()
# Define commodities, orders and bundles
commodity1, commodity2 = get_commodities()
order1, order2, order3, order4 = get_order()
bundle1, bundle2, bundle3 = get_bundles()

order11, order22, order33, order44 = get_order_with_prop()
bundle11, bundle22, bundle33 = get_bundles_with_prop()
bundles = [bundle11, bundle22, bundle33]
bundlesNP = [bundle1, bundle2, bundle3]

TTGraph = OFOND.TravelTimeGraph(network, bundles)
TSGraph = OFOND.TimeSpaceGraph(network, 4)
dates = ["2024-01-01", "2024-01-02", "2024-01-03", "2024-01-04"]
partNumbers = Dict(hash("A123") => "A123", hash("B456") => "B456")
instance = OFOND.Instance(network, TTGraph, TSGraph, bundles, 4, dates, partNumbers)

# Define TravelTimeGraph and TimeSpaceGraph
# TTGraph = OFOND.TravelTimeGraph(network, bundles)
# xdockIdxs = findall(n -> n == xdock, TTGraph.networkNodes)
# portIdxs = findall(n -> n == port_l, TTGraph.networkNodes)
# plantIdxs = findall(n -> n == plant, TTGraph.networkNodes)
# common = vcat(xdockIdxs, portIdxs, plantIdxs)
# allTTNodes = vcat(
#     fill(supplier1, 4), fill(supplier2, 2), fill(xdock, 4), fill(port_l, 4), fill(plant, 1)
# )
# allTTSteps = [0, 1, 2, 3, 0, 1, 0, 1, 2, 3, 0, 1, 2, 3, 0]
# allTTIdxs = [
#     TTGraph.hashToIdx[hash(step, node.hash)] for (step, node) in zip(allTTSteps, allTTNodes)
# ]

# TSGraph = OFOND.TimeSpaceGraph(network, 4)
# allNodes = vcat(
#     fill(supplier1, 4), fill(supplier2, 4), fill(xdock, 4), fill(port_l, 4), fill(plant, 4)
# )
# allSteps = repeat([1, 2, 3, 4], 5)
# allIdxs = [
#     TSGraph.hashToIdx[hash(step, node.hash)] for (step, node) in zip(allSteps, allNodes)
# ]

CAPACITIES = [10, 15, 20, 25]

# Bin-Packing 

@testset "Bin-Packing" begin
    include("test_bin_packing.jl")
end

# Bin Updating

@testset "Bin Updating" begin
    include("test_bin_updating.jl")
end

# Solution Updating 

@testset "Solution Updating" begin
    include("test_solution_updating.jl")
end

# Benchmarks 

@testset "Benchmarks" begin
    # include("test_benchmarks.jl")
end

# Greedy 

@testset "Greedy Utils" begin
    # include("test_greedy_utils.jl")
end

@testset "Greedy" begin
    # include("test_greedy.jl")
end

# Lower Bound 

@testset "Lower Bound Utils" begin
    # include("test_lb_utils.jl")
end

@testset "Lower Bound" begin
    # include("test_lower_bound.jl")
end

# Local Search

@testset "Local Search Utils" begin
    # include("test_ls_utils.jl")
end

@testset "Local Search" begin
    # include("test_local_search.jl")
end

# Large Neighborhood Search 

@testset "LNS Utils" begin
    # include("test_lns_utils.jl")
end

@testset "LNS" begin
    # include("test_lns.jl")
end
