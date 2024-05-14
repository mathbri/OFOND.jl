using OFOND
using Test
using Graphs
using Geodesy
using MetaGraphsNext

println("Testing OFO Network Design Package")

@testset "OFOND.jl" begin
    # Utils file
    @testset "utils.jl" begin
        include("test_utils.jl")
    end
    # Run file
    @testset "run.jl" begin
        # TODO : include("test_run.jl")
    end
    # Structures 
    @testset "Structures" begin
        include("Structures/test_structures.jl")
    end
    # Reading
    @testset "Reading" begin
        # TODO : include("Reading/test_reading.jl")
    end
    # Algorithms
    @testset "Algorithms" begin
        # TODO : include("Algorithms/test_algorithms.jl") 
    end
    # Writing
    @testset "Writing" begin
        # TODO : include("Writing/test_writing.jl")
    end
end
