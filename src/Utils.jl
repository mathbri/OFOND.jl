# Utility functions

# These functions are made to be used across the whole project and are not specifically made for a stucture or specific algorithm

function get_path_nodes(path::Vector{T}) where {T<:AbstractEdge}
    return vcat([src(e) for e in path], [dst(path[end])])
end

function is_path_elementary(path::Vector{UInt})
    if length(path) >= 4
        for (nodeIdx, nodeHash) in enumerate(path)
            if nodeHash in path[(nodeIdx + 1):end]
                # println("Non elementary path found : $path")
                return false
            end
        end
    end
    return true
end

function init_counters(labels::Vector{String})
    return Dict{String,Int}(labels .=> 0)
end

function print_counters(counters::Dict{String,Int})
    for (key, value) in pairs(counters)
        println("$key : $value")
    end
end

function Base.zero(::Type{Vector{Int}})
    return Int[]
end