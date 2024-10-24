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

networkRead = OFOND.NetworkGraph()

@testset "Read and add nodes" begin
    # read file and add nodes
    @test_warn ["Same node already in the network", "Node type not in NodeTypes"] OFOND.read_and_add_nodes!(
        networkRead, joinpath(@__DIR__, "dummy_nodes.csv"); verbose=true
    )
    # the network should be the one in all other tests
    @test nv(networkRead.graph) == 6
    @test ne(networkRead.graph) == 3
    # Testing each field of every node 
    fieldsToTest = (:country, :continent, :isCommon, :volumeCost)
    accounts = ["001", "002", "003", "004", "005", "006"]
    types = [:supplier, :supplier, :supplier, :xdock, :pol, :plant]
    @testset "Nodes equality" for (account, type, tester) in
                                  zip(accounts, types, networkNodes)
        node = networkRead.graph[hash(account, hash(type))]
        @test node == tester
        @test node.country == tester.country
        @test node.continent == tester.continent
        @test node.isCommon == tester.isCommon
        @test node.volumeCost == tester.volumeCost
    end
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
    @test OFOND.src_dst_hash(rows[7]) ==
        (hash("002", hash(Symbol("supplier"))), hash("006", hash(Symbol("plant"))))
    @test OFOND.is_common_arc(rows[10])
    @test !OFOND.is_common_arc(rows[8])

    # Read arc
    row2, row3 = rows[2:3]
    leg = OFOND.read_leg!(counts, row3, OFOND.is_common_arc(row3))
    @test leg == supp1_to_plat
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
    @test leg == OFOND.NetworkArc(:other, 1.0, 1, false, 4.0, true, 0.0, 51)
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
    ] OFOND.read_and_add_legs!(
        networkRead, joinpath(@__DIR__, "dummy_legs.csv"); verbose=true
    )
    # the network should be the one in all other tests
    @test ne(network.graph) == 3 + 9
    @test network.graph[supplier1.hash, xdock.hash] == supp1_to_plat
    @test network.graph[supplier2.hash, xdock.hash] == supp2_to_plat
    @test network.graph[supplier3.hash, xdock.hash] == supp3_to_plat
    @test network.graph[supplier1.hash, plant.hash] == supp1_to_plant
    @test network.graph[supplier2.hash, plant.hash] == supp2_to_plant
    @test network.graph[supplier3.hash, xdock.hash] == supp3_to_plat
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
    row1, row2, row3 = rows[2:4]
    # Bundle hash
    @test OFOND.bundle_hash(row1) == hash("002", hash("006"))
    @test OFOND.bundle_hash(row2) == hash("008", hash("006"))
    # Order hash
    @test OFOND.order_hash(row1) == hash(1, hash("002", hash("006")))
    @test OFOND.order_hash(row2) == hash(1, hash("008", hash("006")))
    # Commodity size
    @test OFOND.com_size(row1) == 15
    @test OFOND.com_size(row2) == 354
    @test OFOND.com_size(row3) == 1
end

@testset "Object getters" begin
    rows = [
        row for row in CSV.File(
            joinpath(@__DIR__, "dummy_commodities.csv");
            types=Dict(
                "supplier_account" => String,
                "customer_account" => String,
                "delivery_date" => String,
            ),
        )
    ]
    row1, row2, row3 = rows[2:4]
    # Get bundle 
    bundles = Dict{UInt,OFOND.Bundle}()
    b1 = OFOND.get_bundle!(bundles, row1, network)
    @test b1 == OFOND.Bundle(supplier2, plant, 1)
    @test bundles == Dict(hash("002", hash("006")) => OFOND.Bundle(supplier2, plant, 1))
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
    @test orders == Dict(hash(1, hash("002", hash("006"))) => OFOND.Order(b1, 1))
    o11 = OFOND.get_order!(orders, row2, b1)
    @test o11 == OFOND.Order(b1, 1)
    @test orders == Dict(
        hash(1, hash("002", hash("006"))) => OFOND.Order(b1, 1),
        hash(1, hash("008", hash("006"))) => OFOND.Order(b1, 1),
    )
    # Add date
    dates = String[]
    row7 = rows[7]
    OFOND.add_date!(dates, row7)
    @test dates == ["", "2024-01-08"]
    OFOND.add_date!(dates, row1)
    @test dates == ["2024-01-01", "2024-01-08"]
end

# bundle11 = OFOND.Bundle(supplier2, plant, [order1], 1, bunH1, 0, 0)
# bundle22 = OFOND.Bundle(supplier1, plant, [order2, order3], 2, bunH2, 0, 0)

# Defining bundles without properties 
bunH1 = hash(supplier1, hash(plant))
bundle1 = OFOND.Bundle(supplier1, plant, [order1], 1, bunH1, 0, 0)

bunH2 = hash(supplier2, hash(plant))
bundle2 = OFOND.Bundle(supplier2, plant, [order2], 2, bunH2, 0, 0)

bunH3 = hash(supplier3, hash(plant))
bundle3 = OFOND.Bundle(supplier3, plant, [order3, order4], 3, bunH3, 0, 0)

bundles = [bundle1, bundle2, bundle3]

@testset "Read commodities" begin
    # read file and add commodities
    bundlesRead, dates, partNums = @test_warn [
        "Supplier unknown in the network", "Customer unknown in the network"
    ] OFOND.read_commodities(network, joinpath(@__DIR__, "dummy_commodities.csv");)
    # the bundles should be the one in all other tests
    @test bundlesRead == bundles
    @testset "Bundle $(idx) equality" for idx in [1, 2, 3]
        @testset "Field $(field)" for field in fieldnames(OFOND.Bundle)
            @test getfield(bundlesRead[idx], field) == getfield(bundles[idx], field)
        end
    end
    # the orders should be equal
    @testset "Order $(idxB).$(idxO) equality" for (idxB, idxO) in
                                                  zip([1, 2, 3, 3], [1, 1, 1, 2])
        @testset "Field $(field)" for field in fieldnames(OFOND.Order)
            if field == :content
                # commodities order hash are read correctly but i set it to 0 and 1 to identify better the commodities in testing 
                content = getfield(bundles[idxB].orders[idxO], field)
                contentRead = getfield(bundlesRead[idxB].orders[idxO], field)
                @test map(com -> com.partNumHash, content) ==
                    map(com -> com.partNumHash, contentRead)
                @test map(com -> com.size, content) == map(com -> com.size, contentRead)
                @test map(com -> com.stockCost, content) ==
                    map(com -> com.stockCost, contentRead)
            else
                @test getfield(bundlesRead[idxB].orders[idxO], field) ==
                    getfield(bundles[idxB].orders[idxO], field)
            end
        end
    end
    # the dates should be equal 
    @test dates == ["2024-01-01", "2024-01-08"]
    @test partNums == Dict{UInt,String}(hash("A123") => "A123", hash("B456") => "B456")
end

@testset "Read instance" begin
    # read instance
    instance = OFOND.read_instance(
        joinpath(@__DIR__, "dummy_nodes.csv"),
        joinpath(@__DIR__, "dummy_legs.csv"),
        joinpath(@__DIR__, "dummy_commodities.csv"),
    )
    @test instance.networkGraph.graph.graph == network.graph.graph
    labelsRead = edge_labels(instance.networkGraph.graph)
    labels = edge_labels(network.graph)
    @test map(l -> instance.networkGraph.graph[l[1], l[2]], labelsRead) ==
        map(l -> network.graph[l[1], l[2]], labels)
    @test instance.bundles == [bundle1, bundle2, bundle3]
    @test instance.dates == ["2024-01-01", "2024-01-08"]
    @test instance.partNumbers == Dict(hash("A123") => "A123", hash("B456") => "B456")
    @test instance.travelTimeGraph.graph == OFOND.TravelTimeGraph().graph
    @test instance.timeSpaceGraph.graph == OFOND.TimeSpaceGraph().graph
end