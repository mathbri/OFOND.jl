# Define supplier, platform, and plant
supplier1 = OFOND.NetworkNode("001", :supplier, "Supp1", LLA(1, 0), "FR", "EU", false, 0.0)
supplier2 = OFOND.NetworkNode("002", :supplier, "Supp2", LLA(0, 1), "FR", "EU", false, 0.0)
xdock = OFOND.NetworkNode("004", :xdock, "XDock1", LLA(2, 1), "FR", "EU", true, 1.0)
port_l = OFOND.NetworkNode("005", :pol, "PortL1", LLA(3, 3), "FR", "EU", true, 0.0)
plant = OFOND.NetworkNode("003", :plant, "Plant1", LLA(4, 4), "FR", "EU", false, 0.0)

# Define arcs between the nodes
supp_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 50)
supp1_to_plant = OFOND.NetworkArc(:direct, 2.0, 2, false, 10.0, false, 1.0, 50)
supp2_to_plant = OFOND.NetworkArc(:direct, 2.0, 1, false, 10.0, false, 1.0, 50)
plat_to_plant = OFOND.NetworkArc(:delivery, 1.0, 1, true, 4.0, false, 1.0, 50)
xdock_to_port = OFOND.NetworkArc(:cross_plat, 1.0, 1, true, 4.0, false, 0.0, 50)
port_to_plant = OFOND.NetworkArc(:oversea, 1.0, 1, true, 4.0, false, 1.0, 50)

# Add them all to the network
network = OFOND.NetworkGraph()
for node in [supplier1, supplier2, xdock, port_l, plant]
    OFOND.add_node!(network, node)
end
OFOND.add_arc!(network, xdock, plant, plat_to_plant)
OFOND.add_arc!(network, supplier1, xdock, supp_to_plat)
OFOND.add_arc!(network, supplier2, xdock, supp_to_plat)
OFOND.add_arc!(network, supplier1, plant, supp1_to_plant)
OFOND.add_arc!(network, supplier2, plant, supp2_to_plant)
OFOND.add_arc!(network, xdock, port_l, xdock_to_port)
OFOND.add_arc!(network, port_l, plant, port_to_plant)

# Define bundles
bpDict = Dict(
    :direct => 3, :cross_plat => 2, :delivery => 2, :oversea => 2, :port_transport => 2
)
commodity1 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 10, 2.5))
bunH1 = hash(supplier1, hash(plant))
order1 = OFOND.Order(
    bunH1, 1, [commodity1, commodity1], hash(1, bunH1), 20, bpDict, 10, 5.0
)
bundle1 = OFOND.Bundle(supplier1, plant, [order1], 1, bunH1, 10, 2)

commodity2 = OFOND.Commodity(1, hash("B456"), OFOND.CommodityData("B456", 15, 3.5))
bunH2 = hash(supplier2, hash(plant))
order2 = OFOND.Order(
    bunH2, 1, [commodity2, commodity2], hash(1, bunH2), 30, bpDict, 15, 7.0
)
bundle2 = OFOND.Bundle(supplier2, plant, [order2], 2, bunH2, 15, 1)

order3 = OFOND.Order(
    bunH1, 1, [commodity2, commodity1], hash(1, bunH1), 25, bpDict, 10, 6.0
)
order4 = OFOND.Order(
    bunH1, 2, [commodity1, commodity2], hash(1, bunH1), 25, bpDict, 10, 6.0
)
bundle3 = OFOND.Bundle(supplier1, plant, [order3, order4], 3, bunH1, 10, 3)

commodity3 = OFOND.Commodity(2, hash("C789"), OFOND.CommodityData("C789", 5, 4.5))

bundles = [bundle1, bundle2, bundle3]

# Define TravelTimeGraph and TimeSpaceGraph
TTGraph = OFOND.TravelTimeGraph(network, bundles)
xdockIdxs = findall(n -> n == xdock, TTGraph.networkNodes)
portIdxs = findall(n -> n == port_l, TTGraph.networkNodes)
plantIdxs = findall(n -> n == plant, TTGraph.networkNodes)
common = vcat(xdockIdxs, portIdxs, plantIdxs)
allTTNodes = vcat(
    fill(supplier1, 4), fill(supplier2, 2), fill(xdock, 4), fill(port_l, 4), fill(plant, 1)
)
allTTSteps = [0, 1, 2, 3, 0, 1, 0, 1, 2, 3, 0, 1, 2, 3, 0]
allTTIdxs = [
    TTGraph.hashToIdx[hash(step, node.hash)] for (step, node) in zip(allTTSteps, allTTNodes)
]

TSGraph = OFOND.TimeSpaceGraph(network, 4)
allNodes = vcat(
    fill(supplier1, 4), fill(supplier2, 4), fill(xdock, 4), fill(port_l, 4), fill(plant, 4)
)
allSteps = repeat([1, 2, 3, 4], 5)
allIdxs = [
    TSGraph.hashToIdx[hash(step, node.hash)] for (step, node) in zip(allSteps, allNodes)
]

# Define instance
dates = [
    Dates.Date(2020, 1, 1),
    Dates.Date(2020, 1, 2),
    Dates.Date(2020, 1, 3),
    Dates.Date(2020, 1, 4),
]
instance = OFOND.Instance(network, TTGraph, TSGraph, bundles, 4, dates)

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
    include("test_benchmarks.jl")
end

# Greedy 

@testset "Greedy Utils" begin
    include("test_greedy_utils.jl")
end

@testset "Greedy" begin
    include("test_greedy.jl")
end

# Lower Bound 

@testset "Lower Bound Utils" begin
    include("test_lb_utils.jl")
end

@testset "Lower Bound" begin
    include("test_lower_bound.jl")
end

# Local Search

@testset "Local Search Utils" begin
    include("test_ls_utils.jl")
end

@testset "Local Search" begin
    include("test_local_search.jl")
end

# Large Neighborhood Search 

@testset "LNS Utils" begin
    include("test_lns_utils.jl")
end

@testset "LNS" begin
    include("test_lns.jl")
end
