# Define supplier, platform, and plant
supplier1 = OFOND.NetworkNode("001", :supplier, "FR", "EU", false, 0.0)
supplier2 = OFOND.NetworkNode("002", :supplier, "GE", "EU", false, 0.0)
xdock = OFOND.NetworkNode("004", :xdock, "FR", "EU", true, 1.0)
port_l = OFOND.NetworkNode("005", :pol, "GE", "EU", true, 0.0)
plant = OFOND.NetworkNode("003", :plant, "FR", "EU", false, 0.0)

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
commodity1 = OFOND.Commodity(0, hash("A123"), 10, 2.5)
bunH1 = hash(supplier1, hash(plant))
order1 = OFOND.Order(
    bunH1, 1, [commodity1, commodity1], hash(1, bunH1), 20, bpDict, 10, 5.0
)
bundle1 = OFOND.Bundle(supplier1, plant, [order1], 1, hash(supplier1, hash(plant)), 10, 3)

commodity2 = OFOND.Commodity(1, hash("B456"), 15, 3.5)
bunH2 = hash(supplier2, hash(plant))
order2 = OFOND.Order(
    bunH2, 1, [commodity2, commodity2], hash(1, bunH2), 30, bpDict, 15, 7.0
)
bundle2 = OFOND.Bundle(supplier2, plant, [order2], 2, hash(supplier2, hash(plant)), 15, 2)

order3 = OFOND.Order(
    bunH1, 1, [commodity2, commodity1], hash(1, bunH1), 25, bpDict, 10, 6.0
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
    bundleNP3.orders, OFOND.Order(hash(supplier1, hash(plant)), 1, [commodity1, commodity2])
)
bundlesNP = [bundleNP1, bundleNP2, bundleNP3]
# Defining instance with empty graphs unless network
instanceNP = OFOND.Instance(
    network,
    OFOND.TravelTimeGraph(),
    OFOND.TimeSpaceGraph(),
    bundlesNP,
    4,
    ["2024-01-01", "2024-01-02", "2024-01-03", "2024-01-04"],
    Dict(hash("A123") => "A123", hash("B456") => "B456"),
)
CAPACITIES = Int[]
instance = OFOND.add_properties(instanceNP, (x, y, z, t) -> 2, CAPACITIES)

@testset "Add properties" begin
    @test instance.timeHorizon == 4
    @test instance.dates == ["2024-01-01", "2024-01-02", "2024-01-03", "2024-01-04"]
    @test instance.partNumbers == Dict(hash("A123") => "A123", hash("B456") => "B456")

    @test instance.networkGraph == network
end

@testset "Bundles equality" begin
    @test instance.bundles[1].supplier == bundles[1].supplier
    @test instance.bundles[1].customer == bundles[1].customer
    @test instance.bundles[1].idx == bundles[1].idx
    @test instance.bundles[1].hash == bundles[1].hash
    @test instance.bundles[1].maxPackSize == bundles[1].maxPackSize
    @test instance.bundles[1].maxDelTime == bundles[1].maxDelTime
    @test instance.bundles[1].orders[1].bundleHash == bundles[1].orders[1].bundleHash
    @test instance.bundles[1].orders[1].deliveryDate == bundles[1].orders[1].deliveryDate
    @test instance.bundles[1].orders[1].hash == bundles[1].orders[1].hash
    @test instance.bundles[1].orders[1].volume == bundles[1].orders[1].volume
    @test instance.bundles[1].orders[1].bpUnits == bundles[1].orders[1].bpUnits
    @test instance.bundles[1].orders[1].minPackSize == bundles[1].orders[1].minPackSize
    @test instance.bundles[1].orders[1].stockCost == bundles[1].orders[1].stockCost
end

@testset "Time Space graph equality" begin
    # Time Space equality
    @test instance.timeSpaceGraph.graph == TSGraph.graph
    @test instance.timeSpaceGraph.timeHorizon == TSGraph.timeHorizon
    @test instance.timeSpaceGraph.networkNodes == TSGraph.networkNodes
    @test instance.timeSpaceGraph.timeStep == TSGraph.timeStep
    @test instance.timeSpaceGraph.networkArcs == TSGraph.networkArcs
    @test instance.timeSpaceGraph.hashToIdx == TSGraph.hashToIdx
    @test instance.timeSpaceGraph.currentCost == TSGraph.currentCost
    @test instance.timeSpaceGraph.commonArcs == TSGraph.commonArcs
end

@testset "Travel Time graph equality" begin
    # Travel Time equality
    @test instance.travelTimeGraph.graph == TTGraph.graph
    @test instance.travelTimeGraph.networkNodes == TTGraph.networkNodes
    @test instance.travelTimeGraph.networkArcs == TTGraph.networkArcs
    @test instance.travelTimeGraph.stepToDel == TTGraph.stepToDel
    @test instance.travelTimeGraph.costMatrix == TTGraph.costMatrix
    @test instance.travelTimeGraph.commonNodes == TTGraph.commonNodes
    @test instance.travelTimeGraph.bundleSrc == TTGraph.bundleSrc
    @test instance.travelTimeGraph.bundleDst == TTGraph.bundleDst
    @test instance.travelTimeGraph.hashToIdx == TTGraph.hashToIdx
end

@testset "sort content" begin
    OFOND.sort_order_content!(instance)
    @test instance.bundles[1].orders[1].content == [commodity1, commodity1]
    @test instance.bundles[2].orders[1].content == [commodity2, commodity2]
    @test instance.bundles[3].orders[1].content == [commodity2, commodity1]
end

@testset "sub instance extraction" begin
    push!(
        instance.bundles[3].orders,
        OFOND.Order(hash(supplier1, hash(plant)), 4, [commodity1, commodity2]),
    )
    subInst = OFOND.extract_sub_instance(instance; country="FR")
    # testing horizon
    @test subInst.timeHorizon == 3
    @test subInst.dates == ["2024-01-01", "2024-01-02", "2024-01-03"]
    # testing network
    @test nv(subInst.networkGraph.graph) == 3
    @test ne(subInst.networkGraph.graph) == 4
    @test all(
        n -> OFOND.is_node_in_country(subInst.networkGraph, n, "FR"),
        vertices(subInst.networkGraph.graph),
    )
    # testing bundles
    @test length(subInst.bundles) == 2
    @test all(bun -> OFOND.is_bundle_in_country(bun, "FR"), subInst.bundles)
    @test OFOND.idx(subInst.bundles) == [1, 2]
    @test subInst.bundles[1].orders == [order1]
    @test subInst.bundles[2].orders == [order3]
end