# Define supplier, platform, and plant
supplier1 = OFOND.NetworkNode("001", :supplier, "Supp1", LLA(1, 0), "FR", "EU", false, 0.0)
supplier2 = OFOND.NetworkNode("002", :supplier, "Supp2", LLA(0, 1), "FR", "EU", false, 0.0)
xdock = OFOND.NetworkNode("004", :xdock, "XDock1", LLA(2, 1), "FR", "EU", true, 1.0)
port_l = OFOND.NetworkNode("005", :port_l, "PortL1", LLA(3, 3), "FR", "EU", true, 0.0)
plant = OFOND.NetworkNode("003", :plant, "Plant1", LLA(4, 4), "FR", "EU", false, 0.0)

# Define arcs between the nodes
supp1_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 50)
supp2_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 50)
supp1_to_plant = OFOND.NetworkArc(:direct, 2.0, 2, false, 10.0, false, 1.0, 50)
supp2_to_plant = OFOND.NetworkArc(:direct, 2.0, 1, false, 10.0, false, 1.0, 50)
plat_to_plant = OFOND.NetworkArc(:delivery, 1.0, 1, true, 4.0, false, 1.0, 50)
xdock_to_port = OFOND.NetworkArc(:cross_plat, 1.0, 1, true, 4.0, false, 0.0, 50)
port_to_plant = OFOND.NetworkArc(:oversea, 1.0, 1, true, 4.0, false, 1.0, 50)

# Add them all to the network
network = OFOND.NetworkGraph()
OFOND.add_node!(network, supplier1)
OFOND.add_node!(network, supplier2)
OFOND.add_node!(network, xdock)
OFOND.add_node!(network, port_l)
OFOND.add_node!(network, plant)
OFOND.add_arc!(network, xdock, plant, plat_to_plant)
OFOND.add_arc!(network, supplier1, xdock, supp1_to_plat)
OFOND.add_arc!(network, supplier2, xdock, supp2_to_plat)
OFOND.add_arc!(network, supplier1, plant, supp1_to_plant)
OFOND.add_arc!(network, supplier2, plant, supp2_to_plant)
OFOND.add_arc!(network, xdock, port_l, xdock_to_port)
OFOND.add_arc!(network, port_l, plant, port_to_plant)

# Define bundles
bpDict = Dict(
    :direct => 2, :cross_plat => 2, :delivery => 2, :oversea => 2, :port_transport => 2
)
commodity1 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("B123", 10, 2.5))
order1 = OFOND.Order(
    hash(supplier1, hash(plant)), 1, [commodity1, commodity1], 20, bpDict, 10, 5.0
)
bundle1 = OFOND.Bundle(supplier1, plant, [order1], 1, hash(supplier1, hash(plant)), 10, 2)

commodity2 = OFOND.Commodity(1, hash("B456"), OFOND.CommodityData("C456", 15, 3.5))
order2 = OFOND.Order(
    hash(supplier2, hash(plant)), 1, [commodity2, commodity2], 30, bpDict, 15, 7.0
)
bundle2 = OFOND.Bundle(supplier2, plant, [order2], 2, hash(supplier2, hash(plant)), 15, 1)

order3 = OFOND.Order(
    hash(supplier1, hash(plant)), 1, [commodity2, commodity1], 25, bpDict, 10, 6.0
)
order4 = OFOND.Order(hash(supplier1, hash(plant)), 2, [commodity1, commodity2])
bundle3 = OFOND.Bundle(supplier1, plant, [order3], 3, hash(supplier1, hash(plant)), 10, 3)

bundles = [bundle1, bundle2, bundle3]

# Define TravelTimeGraph and TimeSpaceGraph
TTGraph = OFOND.TravelTimeGraph(network, bundles)
TSGraph = OFOND.TimeSpaceGraph(network, 4)

# Defining bundles without properties
bundleNP1 = OFOND.Bundle(supplier1, plant, 1)
push!(
    bundleNP1.orders, OFOND.Order(hash(supplier1, hash(plant)), 1, [commodity1, commodity1])
)
bundleNP2 = OFOND.Bundle(supplier2, plant, 2)
push!(
    bundleNP2.orders, OFOND.Order(hash(supplier2, hash(plant)), 1, [commodity2, commodity2])
)
bundleNP3 = OFOND.Bundle(supplier1, plant, 3)
push!(
    bundleNP3.orders, OFOND.Order(hash(supplier1, hash(plant)), 1, [commodity2, commodity1])
)
bundlesNP = [bundleNP1, bundleNP2, bundleNP3]
# Defining instance with empty graphs unless network
instanceNP = OFOND.Instance(
    network,
    OFOND.TravelTimeGraph(),
    OFOND.TimeSpaceGraph(),
    bundlesNP,
    4,
    [Dates(2020, 1, 1), Dates(2020, 1, 2), Dates(2020, 1, 3), Dates(2020, 1, 4)],
)
instance = OFOND.add_properties(instanceNP, (x, y, z) -> 2)

@testset "Add properties" begin
    @test instance.bundles == bundles
    @test instance.timeHorizon == 4
    @test instance.dateHorizon ==
        [Dates(2020, 1, 1), Dates(2020, 1, 2), Dates(2020, 1, 3), Dates(2020, 1, 4)]

    @test instance.networkGraph == network
    @test instance.timeSpaceGraph == TSGraph
    @test instance.travelTimeGraph == TTGraph
end

@testset "sort content" begin
    OFOND.sort_order_content!(instance)
    @test instance.bundles[1].orders[1].content == [commodity1, commodity1]
    @test instance.bundles[2].orders[1].content == [commodity2, commodity2]
    @test instance.bundles[3].orders[1].content == [commodity1, commodity2]
end