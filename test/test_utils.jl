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

@testset "Testing zero" begin
    @test OFOND.zero(Vector{Int}) == Int[]
end

@testset "Elpased time" begin
    @test time() ≈ OFOND.get_elapsed_time(0.0)
    startTime = time()
    sleep(0.5)
    @test 0.5 <= OFOND.get_elapsed_time(startTime) <= 0.55
end

@testset "Variable counters" begin
    model = Model(HiGHS.Optimizer)
    @test num_variables(model) == 0
    @test OFOND.num_integers(model) == 0
    @test OFOND.num_binaries(model) == 0

    @variable(model, x[1:10] >= 0)
    @variable(model, y[1:11], Int)
    @variable(model, z[1:12], Bin)
    @test num_variables(model) == 33
    @test OFOND.num_integers(model) == 11
    @test OFOND.num_binaries(model) == 12
end

@testset "Constraint counters" begin
    model = Model(HiGHS.Optimizer)
    @variable(model, x[1:10] >= 0)
    @test OFOND.num_constr(model) == 0
    @test OFOND.num_path_constr(model) == 0
    @test OFOND.num_pack_constr(model) == 0
    @test OFOND.num_cut_constr(model) == 0

    @constraint(model, path[i in 1:5], x[i] >= 1)
    @constraint(model, packing[j in 1:6], x[j] >= 1)
    @constraint(model, cutSet[k in 1:7], x[k] >= 1)
    @test OFOND.num_constr(model) == 18
    @test OFOND.num_path_constr(model) == 5
    @test OFOND.num_pack_constr(model) == 6
    @test OFOND.num_cut_constr(model) == 7
end