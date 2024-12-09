# Defining instance
TTGraph = OFOND.TravelTimeGraph(network, bundles)
TSGraph = OFOND.TimeSpaceGraph(network, 4)
dates = ["2024-01-01", "2024-01-02", "2024-01-03", "2024-01-04"]
partNumbers = Dict(hash("A123") => "A123", hash("B456") => "B456")
instance = OFOND.Instance(network, TTGraph, TSGraph, bundles, 4, dates, partNumbers)

@testset "Constrcution" begin
    pert = OFOND.Perturbation(
        :test, [1, 2], 3, 4, [[1]], [[2, 3], [4, 5]], sparse([1, 2], [1, 2], [1, 2])
    )
    @test pert.type == :test
    @test pert.bundleIdxs == [1, 2]
    @test pert.src == 3
    @test pert.dst == 4
    @test pert.oldPaths == [[1]]
    @test pert.newPaths == [[2, 3], [4, 5]]
    @test pert.loads == sparse([1 0; 0 2])

    pert = OFOND.Perturbation(:test2, [1, 2], [[1]], sparse([1, 2], [1, 2], [1, 2]))
    @test pert.type == :test2
    @test pert.bundleIdxs == [1, 2]
    @test pert.src == 0
    @test pert.dst == 0
    @test pert.oldPaths == [[1]]
    @test pert.newPaths == Vector{Int}[]
    @test pert.loads == sparse([1 0; 0 2])

    pert = OFOND.Perturbation(:test3, [1, 2], [[1]], [[2, 3]], sparse([2], [2], [2]))
    @test pert.type == :test3
    @test pert.bundleIdxs == [1, 2]
    @test pert.src == 0
    @test pert.dst == 0
    @test pert.oldPaths == [[1]]
    @test pert.newPaths == [[2, 3]]
    @test pert.loads == sparse([0 0; 0 2])

    pert = OFOND.Perturbation(:test4, [1, 2], 3, 4, [[1]], sparse([1, 2], [1, 2], [1, 2]))
    @test pert.type == :test4
    @test pert.bundleIdxs == [1, 2]
    @test pert.src == 3
    @test pert.dst == 4
    @test pert.oldPaths == [[1]]
    @test pert.newPaths == Vector{Int}[]
    @test pert.loads == sparse([1 0; 0 2])
end

@testset "Utils" begin
    pertA = OFOND.Perturbation(
        :test, [1, 2], 3, 4, [[1]], [[2, 3], [4, 5]], sparse([1, 2], [1, 2], [1, 2])
    )
    pertB = OFOND.Perturbation(
        :attract_reduce,
        [1, 2],
        3,
        4,
        [[1]],
        [[2, 3], [4, 5]],
        sparse([1, 2], [1, 2], [1, 2]),
    )
    @test !OFOND.is_attract_reduce(pertA)
    @test OFOND.is_attract_reduce(pertB)
    pertC = OFOND.Perturbation(
        :two_shared_node,
        [1, 3],
        3,
        4,
        [[1]],
        [[2, 3], [4, 5]],
        sparse([1, 2], [1, 2], [1, 2]),
    )
    @test !OFOND.is_two_shared_node(pertA)
    @test OFOND.is_two_shared_node(pertC)
    @test OFOND.number_of_variables(pertA, instance) == 7 + 4 + 12
    @test OFOND.number_of_variables(pertB, instance) == 3 + 12
    @test OFOND.number_of_variables(pertC, instance) == 7 + 7 + 12
    @test OFOND.perturbation_variables(:attract_reduce, [1, 2], instance) == 3 + 12
    @test OFOND.perturbation_variables(:two_shared_node, [1, 3], instance) == 7 + 7 + 12
end