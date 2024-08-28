using OFOND
using Test
using Graphs
using MetaGraphsNext
using SparseArrays
using CSV
using JuMP
using HiGHS

println("Testing OFO Network Design Package")

# TODO : add functions to create the test instance (easier to maintain)

@testset "OFOND.jl" begin
    # Utils file
    @testset "Utils (general)" begin
        # include("test_utils.jl")
    end
    # Structures 
    @testset "Structures" begin
        # include("Structures/test_structures.jl")
    end
    # Reading and Writing
    @testset "Reading-Writing" begin
        # include("ReadingWriting/test_read_write.jl")
    end
    # Algorithms
    @testset "Algorithms" begin
        include("Algorithms/test_algorithms.jl")
    end
    # Run file
    @testset "Run file" begin
        # include("test_run.jl")
    end
end
