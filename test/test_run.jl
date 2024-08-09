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

# Defining bundles without properties
commodity1 = OFOND.Commodity(0, hash("A123"), OFOND.CommodityData("A123", 10, 2.5))
commodity2 = OFOND.Commodity(1, hash("B456"), OFOND.CommodityData("B456", 15, 3.5))

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
    OFOND.TravelTimeGraph(network, bundlesNP),
    OFOND.TimeSpaceGraph(network, 4),
    bundlesNP,
    4,
    [
        Dates.Date(2020, 1, 1),
        Dates.Date(2020, 1, 2),
        Dates.Date(2020, 1, 3),
        Dates.Date(2020, 1, 4),
    ],
)

@testset "Elpased time" begin
    @test time() ≈ OFOND.get_elapsed_time(0.0)
    startTime = time()
    sleep(0.5)
    @test 0.5 <= OFOND.get_elapsed_time(startTime) <= 0.53
end

# fake function that modify the solution
function dummy!(solution, instance)
    solution.bundlePaths[1:end] = [[1, 1] for _ in 1:length(instance.bundles)]
    if length(solution.bins[1, 1]) == 0
        solution.bins[1, 1] = [OFOND.Bin(10, 10, [commodity1])]
    elseif length(solution.bins[1, 1]) <= 10
        push!(solution.bins[1, 1], OFOND.Bin(10, 10, [commodity1]))
    end
end

@testset "Run heuristic" begin
    instance, solution = OFOND.run_heuristic(instanceNP, dummy!)
    # verify that instance has properties now 
    @test instance.bundles[1].maxPackSize == 10
    @test instance.bundles[2].orders[1].volume == 30
    @test instance.bundles[3].orders[1].bpUnits[:delivery] == 1
    # verify solution has been modified
    I1, J1, V1 = findnz(Solution(instance).bins)
    I2, J2, V2 = findnz(solution.bins)
    println(solution.bins[1, 1])
    @test length(I1) + 1 == length(I2)
    @test I1 == I2[2:end]
    @test J1 == J2[2:end]
    @test V1 == V2[2:end]
    @test V2[1] == [OFOND.Bin(10, 10, [commodity1])]
    # run second time with time limit, without presolve and with start sol (previous one)
    startTime = time()
    instanceNP.bundles[2].orders[1] = OFOND.Order(
        hash(supplier2, hash(plant)), 1, [commodity2, commodity2]
    )
    instance2, solution2 = OFOND.run_heuristic(
        instanceNP, dummy!; timeLimit=1, preSolve=false, startSol=solution
    )
    totalTime = OFOND.get_elapsed_time(startTime)
    # verify solution has been modified multiple times
    I1, J1, V1 = findnz(Solution(instance2).bins)
    I2, J2, V2 = findnz(solution2.bins)
    @test length(I1) + 1 == length(I2)
    @test I1 == I2[2:end]
    @test J1 == J2[2:end]
    @test V1 == V2[2:end]
    @test length(V2[1]) > 2
    # verify the elpased time corresponds
    @test 1 < totalTime < 1.1
    # varify instance has no properties
    @test instance2.bundles[1].maxPackSize == 0
    @test instance2.bundles[2].orders[1].volume == 0
    # use lb heuristic and verify the solution is the same 
end