# Define TravelTimeGraph and TimeSpaceGraph
TTGraph = OFOND.TravelTimeGraph(network, bundles)
TSGraph = OFOND.TimeSpaceGraph(network, 4)

# Defining instance with empty graphs and bundles without properties
dates = ["2024-01-01", "2024-01-02", "2024-01-03", "2024-01-04"]
partNumbers = Dict(hash("A123") => "A123", hash("B456") => "B456")
instanceNP = OFOND.Instance(
    network,
    OFOND.TravelTimeGraph(),
    OFOND.TimeSpaceGraph(),
    bundlesNP,
    4,
    dates,
    partNumbers,
)
CAPACITIES = Int[]

# Adding properties
instance = OFOND.add_properties(instanceNP, (x, y, z, t) -> 2, CAPACITIES)

# Testing concrete fields
@testset "Add properties" begin
    @test instance.timeHorizon == 4
    @test instance.dates == ["2024-01-01", "2024-01-02", "2024-01-03", "2024-01-04"]
    @test instance.partNumbers == Dict(hash("A123") => "A123", hash("B456") => "B456")
    @test instance.networkGraph == network
end

# Testtin bundle equality
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

# Testing time space graph equality
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

# Testing travel time graph equality
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
    @test instance.travelTimeGraph.bundleArcs == TTGraph.bundleArcs
end

# Testing sorting all orders content 
@testset "Sorting content" begin
    OFOND.sort_order_content!(instance)
    @test instance.bundles[1].orders[1].content == [commodity1, commodity1]
    @test instance.bundles[2].orders[1].content == [commodity2, commodity2]
    @test instance.bundles[3].orders[1].content == [commodity2, commodity1]
end

order5 = OFOND.Order(hash(supplier3, hash(plant)), 4, [commodity1, commodity2])

# Testing sub instance extraction 
@testset "Extraction" begin
    push!(instance.bundles[3].orders, order5)
    subInst = OFOND.extract_sub_instance(instance; country="FR")
    # testing horizon
    @test subInst.timeHorizon == 3
    @test subInst.dates == ["2024-01-01", "2024-01-02", "2024-01-03"]
    # testing network
    @test nv(subInst.networkGraph.graph) == 5
    @test ne(subInst.networkGraph.graph) == 9
    @test all(
        n -> OFOND.is_node_in_country(subInst.networkGraph, n, "FR"),
        vertices(subInst.networkGraph.graph),
    )
    # testing bundles
    @test length(subInst.bundles) == 2
    @test all(bun -> OFOND.is_bundle_in_country(bun, "FR"), subInst.bundles)
    @test OFOND.idx(subInst.bundles) == [1, 2]
    @test subInst.bundles[1].orders == [order1]
    @test subInst.bundles[2].orders == [order2]
end

# Testing instance splitting
@testset "Splitting" begin
    # By splitting with a time frame of 2, we get two instances on 2 time steps, one with all bundles and one with just the bundle 3
    newInstances = OFOND.split_instance(instance, 2)
    @test length(newInstances) == 2
    # Fetures that are common
    @test all(inst -> inst.timeHorizon == 2, newInstances)
    @test all(inst -> inst.networkGraph == network, newInstances)
    @test all(inst -> inst.partNumbers == partNumbers, newInstances)
    # Features that are not common in the first instance
    @test newInstances[1].dates == ["2024-01-01", "2024-01-02"]
    @test newInstances[1].bundles == [bundle1, bundle2, bundle3]
    @test newInstances[1].bundles[1].orders == [order1]
    @test newInstances[1].bundles[2].orders == [order2]
    @test newInstances[1].bundles[3].orders == [order3, order4]
    @test nv(newInstances[1].travelTimeGraph.graph) == 20
    @test ne(newInstances[1].travelTimeGraph.graph) == 24
    @test nv(newInstances[1].timeSpaceGraph.graph) == 12
    @test ne(newInstances[1].timeSpaceGraph.graph) == 18
    # Features that are not common in the second instance
    @test newInstances[2].dates == ["2024-01-03", "2024-01-04"]
    @test newInstances[2].bundles == [bundle3]
    @test newInstances[2].bundles[1].orders == [order5]
    @test nv(newInstances[2].travelTimeGraph.graph) == 15
    @test ne(newInstances[2].travelTimeGraph.graph) == 12
    @test nv(newInstances[2].timeSpaceGraph.graph) == 12
    @test ne(newInstances[2].timeSpaceGraph.graph) == 18
end

@testset "Outsource instance" begin
    # Changing arcs
    @test OFOND.outsource_arc(supp1_to_plat, 10.0) == supp1_to_plat
    @test OFOND.outsource_arc(supp1_to_plant, 10.0) == supp1_to_plant
    newArc = OFOND.outsource_arc(plat_to_plant, 10.0)
    @testset "Arc changing" for field in fieldnames(OFOND.NetworkArc)
        if field == :unitCost
            @test getfield(newArc, field) != getfield(plat_to_plant, field)
            @test getfield(newArc, field) == 700.0
        elseif field == :isLinear
            @test getfield(newArc, field) != getfield(plat_to_plant, field)
            @test getfield(newArc, field) == true
        else
            @test getfield(newArc, field) == getfield(plat_to_plant, field)
        end
    end
    # Changing whole instance
    newInstance = OFOND.outsource_instance(instance)
    @testset "All arcs changing" for arc in edges(newInstance.travelTimeGraph.graph)
        oldArc = instance.travelTimeGraph.networkArcs[arc.src, arc.dst]
        newArc = newInstance.travelTimeGraph.networkArcs[arc.src, arc.dst]
        if oldArc.type == :outsource || oldArc.type == :direct || oldArc.type == :shortcut
            @test oldArc == newArc
        else
            @test oldArc != newArc
            @test newArc == OFOND.outsource_arc(oldArc, 4 / 70)
        end
    end
end