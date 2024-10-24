# Define nodes, arcs and network
networkNodes = get_nodes()
supplier1, supplier2, supplier3, xdock, port_l, plant = networkNodes
supp1_to_plat, supp2_to_plat, supp3_to_plat, supp1_to_plant, supp2_to_plant, supp3_to_plant, plat_to_plant, xdock_to_port, port_to_plant = get_arcs()
network = get_network()
# Define commodities, orders and bundles
commodity1, commodity2 = get_commodities()
order1, order2, order3, order4 = get_order()
bundle1, bundle2, bundle3 = get_bundles()
bundles = [bundle1, bundle2, bundle3]

@testset "Read instance" begin
    include("test_read_instance.jl")
end

order11, order22, order33, order44 = get_order_with_prop()
bundle11, bundle22, bundle33 = get_bundles_with_prop()
bundles = [bundle11, bundle22, bundle33]
bundlesNP = [bundle1, bundle2, bundle3]

TTGraph = OFOND.TravelTimeGraph(network, bundles)
TSGraph = OFOND.TimeSpaceGraph(network, 4)
dates = ["2024-01-01", "2024-01-02", "2024-01-03", "2024-01-04"]
partNumbers = Dict(hash("A123") => "A123", hash("B456") => "B456")
instance = OFOND.Instance(network, TTGraph, TSGraph, bundles, 4, dates, partNumbers)

supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
TTPath = [supp1FromDel3, xdockFromDel2, portFromDel1, plantFromDel0]

@testset "Read solution" begin
    include("test_read_solution.jl")
end

@testset "Write solution" begin
    include("test_write_solution.jl")
end
