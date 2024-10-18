# Defining a network node
node = OFOND.NetworkNode("account", :supplier, "country", "continent", false, 1.0)
node2 = OFOND.NetworkNode("account2", :xdock, "country", "continent", false, 1.0)
arc = OFOND.NetworkArc(:direct, 1.0, 1, false, 1.0, true, 1.0, 50)
network = OFOND.NetworkGraph()

# Testing mutability
@test !ismutable(node)
@test !ismutable(arc)
@test !ismutable(network)

# Testing constructor
@testset "Constructors" begin
    # Node
    @test node.account == "account"
    @test node.type == :supplier
    @test node.country == "country"
    @test node.continent == "continent"
    @test node.isCommon == false
    @test node.volumeCost == 1.0
    @test node.hash == hash("account", hash(:supplier))
    # Arc
    @test arc.type == :direct
    @test arc.distance == 1.0
    @test arc.travelTime == 1
    @test arc.isCommon == false
    @test arc.unitCost == 1.0
    @test arc.isLinear == true
    @test arc.carbonCost == 1.0
    @test arc.capacity == 50
    # Shortcut 
    @test OFOND.SHORTCUT == OFOND.NetworkArc(
        :shortcut, OFOND.EPS, 1, false, OFOND.EPS, false, OFOND.EPS, 1_000_000
    )
    # Network
    @test isa(network.graph, MetaGraph)
    @test isa(network.graph.graph, DiGraph)
end

# Testing hash and equality 
@testset "Hash and Equality" begin
    @test node == OFOND.NetworkNode("account", :supplier, "c", "c", true, 1.1)
    @test node != OFOND.NetworkNode("account2", :supplier, "c", "c", true, 1.1)
    @test node != OFOND.NetworkNode("account", :supplier2, "c", "c", true, 1.1)
end

# Testing changing node type
newNode = OFOND.change_node_type(node, :pod)
@testset "change_node_type" begin
    @test newNode.account == "account"
    @test newNode.type == :pod
    @test newNode.country == "country"
    @test newNode.continent == "continent"
    @test newNode.isCommon == false
    @test newNode.volumeCost == 1.0
    @test newNode.hash == hash("account", hash(:pod))
end

# Testing add_node!
newNode2 = OFOND.change_node_type(node, :iln)
@testset "add_node!" begin
    # Adding supplier
    added, ignore_type = OFOND.add_node!(network, node)
    @test added
    @test ignore_type == :all_good
    @test haskey(network.graph, node.hash)
    @test network.graph[node.hash] === node
    @test network.graph[node.hash, node.hash] == OFOND.NetworkArc(
        :shortcut, OFOND.EPS, 1, false, OFOND.EPS, false, OFOND.EPS, 1_000_000
    )
    # Adding other node
    added, ignore_type = OFOND.add_node!(network, newNode)
    @test added
    @test ignore_type == :all_good
    @test haskey(network.graph, node.hash)
    @test haskey(network.graph, newNode.hash)
    @test !haskey(network.graph, newNode.hash, newNode.hash)
    # Adding same node 
    warnNode = OFOND.NetworkNode("account", :supplier, "c", "c", true, 1.1)
    added, ignore_type = @test_warn "Same node already in the network" OFOND.add_node!(
        network, warnNode; verbose=true
    )
    @test !added
    @test ignore_type == :same_node
    # Adding node not in Node Types
    warnNode = OFOND.NetworkNode("account12", :type, "c", "c", true, 1.1)
    added, ignore_type = @test_warn "Node type not in NodeTypes" OFOND.add_node!(
        network, warnNode; verbose=true
    )
    @test !added
    @test ignore_type == :unknown_type
end

# Testing add_arc!
a, b = OFOND.add_node!(network, newNode2)
@testset "add_arc" begin
    # Adding an arc
    @test !haskey(network.graph, node.hash, newNode.hash)
    added, ignore_type = OFOND.add_arc!(network, node, newNode, arc)
    @test added
    @test ignore_type == :all_good
    @test haskey(network.graph, node.hash, newNode.hash)
    @test network.graph[node.hash, newNode.hash] === arc
    # Adding an arc already here
    arc2 = OFOND.NetworkArc(:type2, 1.0, 1, false, 1.0, true, 1.0, 50)
    added, ignore_type = @test_warn "Source and destination already have arc data" OFOND.add_arc!(
        network, node, newNode, arc2
    )
    @test !added
    @test ignore_type == :same_arc
    @test network.graph[node.hash, newNode.hash] === arc
    # Adding an arc with unknown source 
    node3 = OFOND.NetworkNode("account3", :type3, "c", "c", false, 1.0)
    added, ignore_type = @test_warn "Source unknown in the network" OFOND.add_arc!(
        network, node3, newNode, arc
    )
    @test !added
    @test ignore_type == :unknown_source
    @test !haskey(network.graph, node3.hash)
    @test !haskey(network.graph, node3.hash, newNode.hash)
    # Adding an arc with unknown destination
    added, ignore_type = @test_warn "Destination unknown in the network" OFOND.add_arc!(
        network, node, node3, arc
    )
    @test !added
    @test ignore_type == :unknown_dest
    @test !haskey(network.graph, node3.hash)
    @test !haskey(network.graph, node.hash, node3.hash)
    # Adding an arc with unknown type
    added, ignore_type = @test_warn "Arc type not in ArcTypes" OFOND.add_arc!(
        network, node, newNode2, arc2
    )
    @test !added
    @test ignore_type == :unknown_type
    @test !haskey(network.graph, node.hash, newNode2.hash)
end

# Testing zero
@testset "Zero" begin
    @test OFOND.zero(OFOND.NetworkNode) == OFOND.NetworkNode("0", :zero, "", "", false, 0.0)
    @test OFOND.zero(OFOND.NetworkArc) ==
        OFOND.NetworkArc(:zero, 0.0, 0, false, 0.0, false, 0.0, 0)
end

# Testing show
@testset "Show" begin
    io = IOBuffer()
    show(io, node)
    content = String(take!(io))
    @test contains(content, "Node(account, supplier)")
end

# Testing is_node_in_ ... 
@testset "Node in contry / continent" begin
    @test !OFOND.is_node_in_country(network, 1, "Fra")
    @test OFOND.is_node_in_country(network, 1, "country")
    @test !OFOND.is_node_in_continent(network, 1, "EU")
    @test OFOND.is_node_in_continent(network, 1, "continent")
end