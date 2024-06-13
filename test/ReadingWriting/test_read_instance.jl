# Create samll versions of renault's file by juste extracting the first lines of the files 

# With this create a small network to test the connection between reading and structures

@testset "Node readers" begin
    # Constants
    @test OFOND.NODE_TYPES == [:supplier, :plant, :xdock, :iln, :port_l, :port_d]
    @test OFOND.COMMON_NODE_TYPES = [:xdock, :iln, :port_l, :port_d]
    counts = Dict([(nodeType, 0) for nodeType in OFOND.NODE_TYPES])
    @test counts == Dict{Symbol,Int}(
        :supplier => 0, :xdock => 0, :iln => 0, :port_l => 0, :port_d => 0, plant => 0
    )

    # Read node
    rows = [row for row in CSV.File("dummy_nodes.csv")]
    row3, row4 = rows[3:4]
    node = OFOND.read_node!(counts, row4)
    @test node ==
        OFOND.NetworkNode("001", :supplier, "Supp1", LLA(1, 0), "FR", "EU", false, 0.0)
    @test counts == Dict{Symbol,Int}(
        :supplier => 0, :xdock => 1, :port_l => 0, :port_d => 0, plant => 0, :iln => 0
    )

    node = OFOND.read_node!(counts, row3)
    @test node ==
        OFOND.NetworkNode("003", :other, "Other1", LLA(0, 0), "FR", "EU", false, 0.0)
    @test counts == Dict{Symbol,Int}(
        :supplier => 0, :xdock => 1, :port_l => 0, :port_d => 0, plant => 0, :iln => 0
    )
end

network = OFOND.NetworkGraph()
supplier1 = OFOND.NetworkNode("001", :supplier, "Supp1", LLA(1, 0), "FR", "EU", false, 0.0)
supplier2 = OFOND.NetworkNode("002", :supplier, "Supp2", LLA(0, 1), "FR", "EU", false, 0.0)
xdock = OFOND.NetworkNode("004", :xdock, "XDock1", LLA(2, 1), "FR", "EU", true, 1.0)
port_l = OFOND.NetworkNode("005", :port_l, "PortL1", LLA(3, 3), "FR", "EU", true, 0.0)
plant = OFOND.NetworkNode("003", :plant, "Plant1", LLA(4, 4), "FR", "EU", false, 0.0)

@testset "Read and add nodes" begin
    # read file and add nodes
    @test_warn ["Same node already in the network", "Node type not in NodeTypes"] OFOND.read_and_add_nodes!(
        network, "dummy_nodes.csv"
    )
    # the network should be the one in all other tests
    @test nv(network.graph) == 5
    @test ne(network.graph) == 2
    node1 = network.graph[hash("001", hash(:supplier))]
    @test node1 == supplier1
    @test node1.name == supplier1.name
    @test node1.coordinates == supplier1.coordinates
    @test node1.country == supplier1.country
    @test node1.continent == supplier1.continent
    @test node1.isCommon == supplier1.isCommon
    @test node1.volumeCost == supplier1.volumeCost
    @test network.graph[hash("002", hash(:supplier))] == supplier2
    @test network.graph[hash("004", hash(:xdock))] == xdock
    @test network.graph[hash("005", hash(:port_l))] == port_l
    @test network.graph[hash("003", hash(:plant))] == plant
end

supp_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 50)

@testset "Leg readers" begin
    # Constants
    @test OFOND.ARC_TYPES = [
        :direct, :outsource, :cross_plat, :delivery, :oversea, :port_transport, :shortcut
    ]
    @test OFOND.BP_ARC_TYPES = [:direct, :cross_plat, :delivery, :oversea, :port_transport]
    @test OFOND.COMMON_ARC_TYPES = [:cross_plat, :delivery, :oversea, :port_transport]
    counts = Dict([(arcType, 0) for arcType in OFOND.ARC_TYPES])
    @test counts == Dict{Symbol,Int}(
        :direct => 0,
        :outsource => 0,
        :delivery => 0,
        :cross_plat => 0,
        :oversea => 0,
        :port_transport => 0,
    )

    rows = [row for row in CSV.File("dummy_legs.csv")]
    # Row readers
    @test src_dst_hash(rows[1]) ==
        (hash("001", Symbol("supplier")), hash("004", Symbol("xdock")))
    @test src_dst_hash(rows[6]) ==
        (hash("002", Symbol("supplier")), hash("003", Symbol("plant")))
    @test is_common_arc(rows[1])
    @test !is_common_arc(rows[6])

    # Read arc
    rows = [row for row in CSV.File("dummy_legs.csv")]
    row2, row3 = rows[2:3]
    leg = OFOND.read_leg!(counts, row3)
    @test leg == supp_to_plat
    @test counts == Dict{Symbol,Int}(
        :direct => 0,
        :outsource => 1,
        :delivery => 0,
        :cross_plat => 0,
        :oversea => 0,
        :port_transport => 0,
    )
    leg = OFOND.read_leg!(counts, row3)
    @test leg == OFOND.NetworkArc(:other, 1.0, 1, false, 4.0, true, 0.0, 50)
    @test counts == Dict{Symbol,Int}(
        :direct => 0,
        :outsource => 1,
        :delivery => 0,
        :cross_plat => 0,
        :oversea => 0,
        :port_transport => 0,
    )
end

supp1_to_plant = OFOND.NetworkArc(:direct, 2.0, 2, false, 10.0, false, 1.0, 50)
supp2_to_plant = OFOND.NetworkArc(:direct, 2.0, 1, false, 10.0, false, 1.0, 50)
plat_to_plant = OFOND.NetworkArc(:delivery, 1.0, 1, true, 4.0, false, 1.0, 50)
xdock_to_port = OFOND.NetworkArc(:cross_plat, 1.0, 1, true, 4.0, false, 0.0, 50)
port_to_plant = OFOND.NetworkArc(:oversea, 1.0, 1, true, 4.0, false, 1.0, 50)

@testset "Read and add legs" begin
    # read file and add arcs
    @test_warn [
        "Source and destination already have arc data",
        "Source unknown in the network",
        "Arc type not in ArcTypes",
    ] OFOND.read_and_add_legs!(network, "dummy_legs.csv")
    # the network should be the one in all other tests
    @test ne(network.graph) == 2 + 7
    @test network.graph[supplier1.hash, xdock.hash] == supp_to_plat
    @test network.graph[supplier2.hash, xdock.hash] == supp_to_plat
    @test network.graph[supplier1.hash, plant.hash] == supp1_to_plant
    @test network.graph[supplier2.hash, plant.hash] == supp2_to_plant
    @test network.graph[xdock.hash, plant.hash] == plat_to_plant
    @test network.graph[xdock.hash, port_l.hash] == xdock_to_port
    @test network.graph[port_l.hash, plant.hash] == port_to_plant
end

@testset "Commodity readers / getters" begin
    # Bundle and order hash
    # Commodity size and cost
end

@testset "Read commodities" begin
    # read file and add commodities
end

@testset "Read instance" begin
    # read instance
end