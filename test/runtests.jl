using OFOND
using Test
using Graphs
using MetaGraphsNext
using SparseArrays
using CSV
using JuMP
using HiGHS
using IterTools

println("Testing OFO Network Design Package")

function get_nodes()
    # Define suppliers, platforms, and plant
    supplier1 = OFOND.NetworkNode("001", :supplier, "FR", "EU", false, 0.0)
    supplier2 = OFOND.NetworkNode("002", :supplier, "FR", "EU", false, 0.0)
    supplier3 = OFOND.NetworkNode("003", :supplier, "GE", "EU", false, 0.0)
    xdock = OFOND.NetworkNode("004", :xdock, "FR", "EU", true, 1.0)
    port_l = OFOND.NetworkNode("005", :pol, "FR", "EU", true, 0.0)
    plant = OFOND.NetworkNode("006", :plant, "FR", "EU", false, 0.0)
    return supplier1, supplier2, supplier3, xdock, port_l, plant
end

function get_arcs()
    # Define arcs between the nodes
    supp1_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 50)
    supp2_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 51)
    supp3_to_plat = OFOND.NetworkArc(:outsource, 1.0, 1, false, 4.0, true, 0.0, 52)
    supp1_to_plant = OFOND.NetworkArc(:direct, 2.0, 2, false, 10.0, false, 1.0, 50)
    supp2_to_plant = OFOND.NetworkArc(:direct, 2.0, 1, false, 10.0, false, 1.0, 51)
    supp3_to_plant = OFOND.NetworkArc(:direct, 2.0, 2, false, 10.0, false, 1.0, 52)
    plat_to_plant = OFOND.NetworkArc(:delivery, 1.0, 1, true, 4.0, false, 1.0, 50)
    xdock_to_port = OFOND.NetworkArc(:cross_plat, 1.0, 1, true, 4.0, false, 0.0, 50)
    port_to_plant = OFOND.NetworkArc(:oversea, 1.0, 1, true, 4.0, false, 1.0, 50)
    return supp1_to_plat,
    supp2_to_plat,
    supp3_to_plat,
    supp1_to_plant,
    supp2_to_plant,
    supp3_to_plant,
    plat_to_plant,
    xdock_to_port,
    port_to_plant
end

function get_network()
    supplier1, supplier2, supplier3, xdock, port_l, plant = get_nodes()
    supp1_to_plat, supp2_to_plat, supp3_to_plat, supp1_to_plant, supp2_to_plant, supp3_to_plant, plat_to_plant, xdock_to_port, port_to_plant = get_arcs()
    network = OFOND.NetworkGraph()
    OFOND.add_node!(network, supplier1)
    OFOND.add_node!(network, supplier2)
    OFOND.add_node!(network, supplier3)
    OFOND.add_node!(network, xdock)
    OFOND.add_node!(network, port_l)
    OFOND.add_node!(network, plant)
    OFOND.add_arc!(network, xdock, plant, plat_to_plant)
    OFOND.add_arc!(network, supplier1, xdock, supp1_to_plat)
    OFOND.add_arc!(network, supplier2, xdock, supp2_to_plat)
    OFOND.add_arc!(network, supplier3, xdock, supp3_to_plat)
    OFOND.add_arc!(network, supplier1, plant, supp1_to_plant)
    OFOND.add_arc!(network, supplier2, plant, supp2_to_plant)
    OFOND.add_arc!(network, supplier3, plant, supp3_to_plant)
    OFOND.add_arc!(network, xdock, port_l, xdock_to_port)
    OFOND.add_arc!(network, port_l, plant, port_to_plant)
    return network
end

function get_commodities()
    commodity1 = OFOND.Commodity(0, hash("A123"), 10, 2.5)
    commodity2 = OFOND.Commodity(1, hash("B456"), 15, 3.5)
    return commodity1, commodity2
end

function get_order()
    commodity1, commodity2 = get_commodities()
    supplier1, supplier2, supplier3, xdock, port_l, plant = get_nodes()
    bunH1 = hash(supplier1, hash(plant))
    order1 = OFOND.Order(bunH1, 1, [commodity1, commodity1])
    bunH2 = hash(supplier2, hash(plant))
    order2 = OFOND.Order(bunH2, 1, [commodity2, commodity2])
    bunH3 = hash(supplier3, hash(plant))
    order3 = OFOND.Order(bunH3, 1, [commodity1, commodity2])
    order4 = OFOND.Order(bunH3, 2, [commodity1, commodity2])
    return order1, order2, order3, order4
end

function get_bundles()
    supplier1, supplier2, supplier3, xdock, port_l, plant = get_nodes()
    order1, order2, order3, order4 = get_order()
    bunH1 = hash(supplier1, hash(plant))
    bundle1 = OFOND.Bundle(supplier1, plant, [order1], 1, bunH1, 10, 2)
    bunH2 = hash(supplier2, hash(plant))
    bundle2 = OFOND.Bundle(supplier2, plant, [order2], 2, bunH2, 15, 1)
    bunH3 = hash(supplier3, hash(plant))
    bundle3 = OFOND.Bundle(supplier3, plant, [order3, order4], 3, bunH3, 10, 3)
    return bundle1, bundle2, bundle3
end

function get_order_with_prop()
    commodity1, commodity2 = get_commodities()
    supplier1, supplier2, supplier3, xdock, port_l, plant = get_nodes()
    bpDict = Dict(
        :direct => 2, :cross_plat => 2, :delivery => 2, :oversea => 2, :port_transport => 2
    )
    bunH1 = hash(supplier1, hash(plant))
    order11 = OFOND.Order(
        bunH1, 1, [commodity1, commodity1], hash(1, bunH1), 20, bpDict, 10, 5.0
    )
    bunH2 = hash(supplier2, hash(plant))
    order22 = OFOND.Order(
        bunH2, 1, [commodity2, commodity2], hash(1, bunH2), 30, bpDict, 15, 7.0
    )
    bunH3 = hash(supplier3, hash(plant))
    order33 = OFOND.Order(
        bunH3, 1, [commodity2, commodity1], hash(1, bunH3), 25, bpDict, 10, 6.0
    )
    order44 = OFOND.Order(
        bunH3, 2, [commodity2, commodity1], hash(2, bunH3), 25, bpDict, 10, 6.0
    )
    return order11, order22, order33, order44
end

function get_bundles_with_prop()
    supplier1, supplier2, supplier3, xdock, port_l, plant = get_nodes()
    order11, order22, order33, order44 = get_order_with_prop()
    bunH1 = hash(supplier1, hash(plant))
    bundle1 = OFOND.Bundle(supplier1, plant, [order11], 1, bunH1, 10, 3)
    bunH2 = hash(supplier2, hash(plant))
    bundle2 = OFOND.Bundle(supplier2, plant, [order22], 2, bunH2, 15, 2)
    bunH3 = hash(supplier3, hash(plant))
    bundle3 = OFOND.Bundle(supplier3, plant, [order33, order44], 3, bunH3, 10, 3)
    return bundle1, bundle2, bundle3
end

@testset "OFOND.jl" begin
    # Utils file
    @testset "Utils (general)" begin
        include("test_utils.jl")
    end
    # Structures 
    @testset "Structures" begin
        include("Structures/test_structures.jl")
    end
    # Reading and Writing
    @testset "Reading-Writing" begin
        include("ReadingWriting/test_read_write.jl")
    end
    # Algorithms
    @testset "Algorithms" begin
        include("Algorithms/test_algorithms.jl")
    end
    # Run file
    @testset "Run" begin
        include("test_run.jl")
    end
end
