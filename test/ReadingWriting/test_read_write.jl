# Defining common network (filled in test read instance)
network = OFOND.NetworkGraph()
supplier1 = OFOND.NetworkNode("001", :supplier, "Supp1", LLA(1, 0), "FR", "EU", false, 0.0)
supplier2 = OFOND.NetworkNode("002", :supplier, "Supp2", LLA(0, 1), "FR", "EU", false, 0.0)
xdock = OFOND.NetworkNode("004", :xdock, "XDock1", LLA(2, 1), "FR", "EU", true, 1.0)
port_l = OFOND.NetworkNode("005", :pol, "PortL1", LLA(3, 3), "FR", "EU", true, 0.0)
plant = OFOND.NetworkNode("003", :plant, "Plant1", LLA(4, 4), "FR", "EU", false, 0.0)

supp_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 50)
supp1_to_plant = OFOND.NetworkArc(:direct, 2.0, 2, false, 10.0, false, 1.0, 50)
supp2_to_plant = OFOND.NetworkArc(:direct, 2.0, 1, false, 10.0, false, 1.0, 50)
plat_to_plant = OFOND.NetworkArc(:delivery, 1.0, 1, false, 4.0, false, 1.0, 50)
xdock_to_port = OFOND.NetworkArc(:cross_plat, 1.0, 1, true, 4.0, false, 0.0, 50)
port_to_plant = OFOND.NetworkArc(:oversea, 1.0, 1, false, 4.0, false, 1.0, 50)

# Defining common bundles
bunH1 = hash(supplier2, hash(plant))
comData2 = OFOND.CommodityData("A123", 10, 2.5)
comData1 = OFOND.CommodityData("B456", 15, 3.5)

commodity1 = OFOND.Commodity(hash(1, bunH1), hash("B456"), comData1)
order1 = OFOND.Order(bunH1, 1, [commodity1, commodity1])
bundle1 = OFOND.Bundle(supplier2, plant, [order1], 1, bunH1, 15, 2)

bunH2 = hash(supplier1, hash(plant))
commodity2 = OFOND.Commodity(hash(1, bunH2), hash("A123"), comData2)
commodity3 = OFOND.Commodity(hash(1, bunH2), hash("B456"), comData1)
commodity4 = OFOND.Commodity(hash(2, bunH2), hash("A123"), comData2)
commodity5 = OFOND.Commodity(hash(2, bunH2), hash("B456"), comData1)

order2 = OFOND.Order(bunH2, 1, [commodity2, commodity3])
order3 = OFOND.Order(bunH2, 2, [commodity4, commodity5])
bundle2 = OFOND.Bundle(supplier1, plant, [order2, order3], 2, bunH2, 15, 3)

@testset "Read instance" begin
    include("test_read_instance.jl")
end

bundles = [bundle1, bundle2]
TTGraph = OFOND.TravelTimeGraph(network, bundles)
TSGraph = OFOND.TimeSpaceGraph(network, 4)
dates = [
    Dates.Date(2020, 1, 1),
    Dates.Date(2020, 1, 2),
    Dates.Date(2020, 1, 3),
    Dates.Date(2020, 1, 4),
]
instance = OFOND.Instance(network, TTGraph, TSGraph, bundles, 4, dates)

@testset "Read solution" begin
    include("test_read_solution.jl")
end

@testset "Write solution" begin
    include("test_write_solution.jl")
end
