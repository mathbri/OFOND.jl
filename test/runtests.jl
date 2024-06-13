using OFOND
using Test
using Graphs
using Geodesy
using MetaGraphsNext
using SparseArrays
using Dates
using CSV

println("Testing OFO Network Design Package")

@testset "OFOND.jl" begin
    # Utils file
    @testset "Utils (general)" begin
        include("test_utils.jl")
    end
    # Run file
    @testset "Run file" begin
        # TODO : include("test_run.jl")
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
end
