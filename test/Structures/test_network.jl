# Defining a network node
node = OFOND.NetworkNode(
    "account", :type, "name", LLA(1, 1), "country", "continent", false, 1.0
)
node2 = OFOND.NetworkNode(
    "account2", :type2, "name", LLA(1, 1), "country", "continent", false, 1.0
)
arc = OFOND.NetworkArc(:type, 1.0, 1, false, 1.0, true, 1.0, 50)
network = OFOND.NetworkGraph()

# Testing mutability
@test !ismutable(node)
@test !ismutable(arc)
@test !ismutable(network)

# Unit tests for Network structure and methods
@testset "Constructors" begin
    # Testing Node
    @test node.account == "account"
    @test node.type == :type
    @test node.name == "name"
    @test node.coordinates == LLA(1, 1)
    @test node.country == "country"
    @test node.continent == "continent"
    @test node.isCommon == false
    @test node.volumeCost == 1.0
    @test node.hash == hash("account", hash(:type))

    # Testing equality
    @test node == OFOND.NetworkNode("account", :type, "n2", LLA(2, 2), "c", "c", true, 1.1)
    @test node != node2

    # Testing Network
    @test isa(network.graph, MetaGraph)
    @test isa(network.graph.graph, DiGraph)
end

newNode = OFOND.change_node_type(node, :port_d)
@testset "change_node_type" begin
    # Testing changing node type
    @test newNode.account == "account"
    @test newNode.type == :port_d
    @test newNode.name == "name"
    @test newNode.coordinates == LLA(1, 1)
    @test newNode.country == "country"
    @test newNode.continent == "continent"
    @test newNode.isCommon == false
    @test newNode.volumeCost == 1.0
    @test newNode.hash == hash("account", hash(:port_d))
end

newNode2 = OFOND.change_node_type(node, :supplier)
@testset "add_node" begin
    # Testing add_node! method
    OFOND.add_node!(network, node)
    @test haskey(network.graph, node.hash)
    @test network.graph[node.hash] === node

    # Testing add_node! method with changed node type
    OFOND.add_node!(network, newNode)
    @test haskey(network.graph, node.hash)
    @test haskey(network.graph, newNode.hash)

    # Testing add_node! method with supplier
    OFOND.add_node!(network, newNode2)
    @test haskey(network.graph, newNode2.hash)
    @test haskey(network.graph, newNode2.hash, newNode2.hash)
    @test network.graph[newNode2.hash, newNode2.hash] == OFOND.NetworkArc(
        :shortcut, OFOND.EPS, 1, false, OFOND.EPS, false, OFOND.EPS, 1_000_000
    )

    # Testing add_node! method with warnings
    warnNode = OFOND.NetworkNode("account", :type, "n2", LLA(2, 2), "c", "c", true, 1.1)
    @test_logs (:warn, "Same node already in the network") OFOND.add_node!(
        network, warnNode
    )
end

@testset "add_arc" begin
    # Testing add_arc! method
    @test !haskey(network.graph, node.hash, newNode.hash)
    OFOND.add_arc!(network, node, newNode, arc)
    @test haskey(network.graph, node.hash, newNode.hash)
    @test network.graph[node.hash, newNode.hash] === arc

    # Testing add_arc! method with warnings
    node3 = OFOND.NetworkNode("account3", :type3, "n3", LLA(1, 1), "c", "c", false, 1.0)
    arc2 = OFOND.NetworkArc(:type2, 1.0, 1, false, 1.0, true, 1.0, 50)
    @test_logs (:warn, "Source and destination already have arc data") OFOND.add_arc!(
        network, node, newNode, arc2
    )
    @test network.graph[node.hash, newNode.hash] === arc

    @test_logs (:warn, "Source unknown in the network") OFOND.add_arc!(
        network, node3, newNode, arc
    )
    OFOND.add_arc!(network, node3, newNode, arc)
    @test !haskey(network.graph, node3.hash)
    @test !haskey(network.graph, node3.hash, newNode.hash)

    @test_logs (:warn, "Destination unknown in the network") OFOND.add_arc!(
        network, node, node3, arc
    )
    OFOND.add_arc!(network, node, node3, arc)
    @test !haskey(network.graph, node3.hash)
    @test !haskey(network.graph, node.hash, node3.hash)
end

@testset "Testing zero" begin
    @test OFOND.zero(OFOND.NetworkArc) ==
        OFOND.NetworkArc(:zero, 0.0, 0, false, 0.0, false, 0.0, 0)
end