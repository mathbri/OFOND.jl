@testset "get_path_nodes" begin
    path = [Edge(1, 2), Edge(2, 3), Edge(3, 4)]
    @test OFOND.get_path_nodes(path) == [1, 2, 3, 4]
end

@testset "is_path_elementary" begin
    @test OFOND.is_path_elementary(UInt.([1, 2, 2])) == true
    @test OFOND.is_path_elementary(UInt.([1, 2, 3, 4])) == true
    @test OFOND.is_path_elementary(UInt.([1, 2, 2, 3, 4])) == false
end

@testset "init_counters" begin
    labels = ["A", "B", "C"]
    @test OFOND.init_counters(labels) == Dict{String,Int}("A" => 0, "B" => 0, "C" => 0)
end

@testset "print_counters" begin
    counters = Dict("Label A" => 2, "Label B" => 1, "Label C" => 0)
    OFOND.print_counters(counters)
end
