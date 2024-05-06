using OFOND
using Test
using Graphs

println("Testing OFO Network Design Package")

@testset "OFOND.jl" begin
    @testset "utils.jl" begin
        include("test_utils.jl")
    end
end
