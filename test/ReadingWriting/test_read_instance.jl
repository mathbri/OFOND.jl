# Create samll versions of renault's file by juste extracting the first lines of the files 

@testset "Node readers" begin
    # Constants
    @test OFOND.NODE_TYPES == [:supplier, :plant, :xdock, :iln, :pol, :pod]
    @test OFOND.COMMON_NODE_TYPES == [:xdock, :iln, :pol, :pod]
    counts = Dict([(nodeType, 0) for nodeType in OFOND.NODE_TYPES])
    @test counts == Dict{Symbol,Int}(
        :supplier => 0, :xdock => 0, :iln => 0, :pol => 0, :pod => 0, :plant => 0
    )

    # Read node
    rows = [
        row for row in CSV.File(
            joinpath(@__DIR__, "dummy_nodes.csv");
            types=Dict("point_account" => String, "point_type" => String),
        )
    ]
    row3, row4 = rows[3:4]
    node = OFOND.read_node!(counts, row3)
    @test node == OFOND.NetworkNode("002", :supplier, "FR", "EU", false, 0.0)
    @test counts == Dict{Symbol,Int}(
        :supplier => 1, :xdock => 0, :pol => 0, :pod => 0, :plant => 0, :iln => 0
    )

    node = OFOND.read_node!(counts, row4)
    @test node == OFOND.NetworkNode("003", :other, "FR", "EU", false, 0.0)
    @test counts == Dict{Symbol,Int}(
        :supplier => 1, :xdock => 0, :pol => 0, :pod => 0, :plant => 0, :iln => 0
    )
end

@testset "Read and add nodes" begin
    # read file and add nodes
    @test_warn ["Same node already in the network", "Node type not in NodeTypes"] OFOND.read_and_add_nodes!(
        network, joinpath(@__DIR__, "dummy_nodes.csv")
    )
    # the network should be the one in all other tests
    @test nv(network.graph) == 5
    @test ne(network.graph) == 2
    node1 = network.graph[hash("001", hash(:supplier))]
    @test node1 == supplier1
    @test node1.country == supplier1.country
    @test node1.continent == supplier1.continent
    @test node1.isCommon == supplier1.isCommon
    @test node1.volumeCost == supplier1.volumeCost
    @test network.graph[hash("002", hash(:supplier))] == supplier2
    @test network.graph[hash("004", hash(:xdock))] == xdock
    @test network.graph[hash("005", hash(:pol))] == port_l
    @test network.graph[hash("003", hash(:plant))] == plant
end

@testset "Leg readers" begin
    # Constants
    @test OFOND.ARC_TYPES == [
        :direct, :outsource, :cross_plat, :delivery, :oversea, :port_transport, :shortcut
    ]
    @test OFOND.BP_ARC_TYPES == [:direct, :cross_plat, :delivery, :oversea, :port_transport]
    @test OFOND.COMMON_ARC_TYPES == [:cross_plat, :delivery, :oversea, :port_transport]
    counts = Dict([(arcType, 0) for arcType in OFOND.ARC_TYPES])
    @test counts == Dict{Symbol,Int}(
        :direct => 0,
        :outsource => 0,
        :delivery => 0,
        :cross_plat => 0,
        :oversea => 0,
        :port_transport => 0,
        :shortcut => 0,
    )

    columns = ["src_account", "dst_account", "src_type", "dst_type", "leg_type"]
    rows = [
        row for row in CSV.File(
            joinpath(@__DIR__, "dummy_legs.csv");
            types=Dict([(column, String) for column in columns]),
        )
    ]
    # Row readers
    @test OFOND.src_dst_hash(rows[1]) ==
        (hash("001", hash(Symbol("supplier"))), hash("004", hash(Symbol("xdock"))))
    @test OFOND.src_dst_hash(rows[6]) ==
        (hash("002", hash(Symbol("supplier"))), hash("003", hash(Symbol("plant"))))
    @test OFOND.is_common_arc(rows[8])
    @test !OFOND.is_common_arc(rows[6])

    # Read arc
    row2, row3 = rows[2:3]
    leg = OFOND.read_leg!(counts, row3, OFOND.is_common_arc(row3))
    @test leg == supp_to_plat
    @test counts == Dict{Symbol,Int}(
        :direct => 0,
        :outsource => 1,
        :delivery => 0,
        :cross_plat => 0,
        :oversea => 0,
        :port_transport => 0,
        :shortcut => 0,
    )
    leg = OFOND.read_leg!(counts, row2, OFOND.is_common_arc(row2))
    @test leg == OFOND.NetworkArc(:other, 1.0, 1, false, 4.0, true, 0.0, 50)
    @test counts == Dict{Symbol,Int}(
        :direct => 0,
        :outsource => 1,
        :delivery => 0,
        :cross_plat => 0,
        :oversea => 0,
        :port_transport => 0,
        :shortcut => 0,
    )
end

@testset "Read and add legs" begin
    # read file and add arcs
    @test_warn [
        "Source and destination already have arc data",
        "Source unknown in the network",
        "Arc type not in ArcTypes",
    ] OFOND.read_and_add_legs!(network, joinpath(@__DIR__, "dummy_legs.csv"))
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

@testset "Commodity readers" begin
    rows = [
        row for row in CSV.File(
            joinpath(@__DIR__, "dummy_commodities.csv");
            types=Dict("supplier_account" => String, "customer_account" => String),
        )
    ]
    row1, row2, row3 = rows[1:3]
    # Bundle hash
    @test OFOND.bundle_hash(row1) == hash("002", hash("003"))
    @test OFOND.bundle_hash(row2) == hash("008", hash("003"))
    # Order hash
    @test OFOND.order_hash(row1) == hash(1, hash("002", hash("003")))
    @test OFOND.order_hash(row2) == hash(1, hash("008", hash("003")))
    # Commodity size
    @test OFOND.com_size(row1) == 1500
    @test OFOND.com_size(row2) == 354
    @test OFOND.com_size(row3) == 1
end

@testset "Object getters" begin
    rows = [
        row for row in CSV.File(
            joinpath(@__DIR__, "dummy_commodities.csv");
            types=Dict("supplier_account" => String, "customer_account" => String),
        )
    ]
    row1, row2, row3 = rows[1:3]
    # Get bundle 
    bundles = Dict{UInt,OFOND.Bundle}()
    b1 = OFOND.get_bundle!(bundles, row1, network)
    @test b1 == OFOND.Bundle(supplier2, plant, 1)
    @test bundles == Dict(hash("002", hash("003")) => OFOND.Bundle(supplier2, plant, 1))
    b11 = OFOND.get_bundle!(bundles, row1, network)
    @test b11 === b1
    b12 = @test_warn "Supplier unknown in the network" OFOND.get_bundle!(
        bundles, row2, network
    )
    @test b12 === nothing
    b13 = @test_warn "Customer unknown in the network" OFOND.get_bundle!(
        bundles, row3, network
    )
    @test b13 === nothing
    # Get order 
    orders = Dict{UInt,OFOND.Order}()
    o1 = OFOND.get_order!(orders, row1, b1)
    @test o1 == OFOND.Order(b1, 1)
    @test orders == Dict(hash(1, hash("002", hash("003"))) => OFOND.Order(b1, 1))
    o11 = OFOND.get_order!(orders, row2, b1)
    @test o11 == OFOND.Order(b1, 1)
    @test orders == Dict(
        hash(1, hash("002", hash("003"))) => OFOND.Order(b1, 1),
        hash(1, hash("008", hash("003"))) => OFOND.Order(b1, 1),
    )
end

bundle11 = OFOND.Bundle(supplier2, plant, [order1], 1, bunH1, 0, 0)
bundle22 = OFOND.Bundle(supplier1, plant, [order2, order3], 2, bunH2, 0, 0)

@testset "Read commodities" begin
    # read file and add commodities
    bundles, dates, partNums = @test_warn [
        "Supplier unknown in the network", "Customer unknown in the network"
    ] OFOND.read_commodities(network, joinpath(@__DIR__, "dummy_commodities.csv");)
    # the bundles should be the one in all other tests
    @test bundles == [bundle11, bundle22]
    bundlesTest = [bundle11, bundle22]
    @testset "All fields equal bundle $(idx)" for idx in [1, 2]
        @testset "Field $(field)" for field in fieldnames(OFOND.Bundle)
            @test getfield(bundlesTest[idx], field) == getfield(bundles[idx], field)
        end
    end
    # the orders should be equal
    @testset "All fields equal order $(idxB).$(idxO)" for (idxB, idxO) in
                                                          zip([1, 2, 2], [1, 1, 2])
        ordersTest = [[order1], [order2, order3]]
        @testset "Field $(field)" for field in fieldnames(OFOND.Order)
            @test getfield(ordersTest[idxB][idxO], field) ==
                getfield(bundles[idxB].orders[idxO], field)
        end
    end
end

@testset "Read instance" begin
    # read instance
    instance = OFOND.read_instance(
        joinpath(@__DIR__, "dummy_nodes.csv"),
        joinpath(@__DIR__, "dummy_legs.csv"),
        joinpath(@__DIR__, "dummy_commodities.csv"),
    )
    @test instance.networkGraph.graph == network.graph
    @test instance.bundles == [bundle1, bundle2]
    @test instance.dates == ["2024-01-01", "2024-01-08"]
    @test instance.partNumbers == Dict(hash("A123") => "A123", hash("B456") => "B456")
    @test instance.travelTimeGraph.graph == OFOND.TravelTimeGraph().graph
    @test instance.timeSpaceGraph.graph == OFOND.TimeSpaceGraph().graph
end