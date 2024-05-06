using OFOND
using Test
using Graphs

println("Testing OFO Network Design Package")

@testset "OFOND.jl" begin
    # Utils file
    @testset "utils.jl" begin
        include("test_utils.jl")
    end
    # Run file
    # @testset "run.jl" begin
    #     include("test_run.jl")
    # end
    # Structures 
    @testset "Structures" begin
        include("Structures/test_structures.jl")
    end
    # Reading
    # Algorithms
    # Writing
end
