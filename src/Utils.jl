# Utility functions

# These functions are made to be used across the whole project and are not specifically made for a stucture or specific algorithm

function get_path_nodes(path::Vector{Edge})
    return vcat([src(e) for e in path], [dst(path[1])])
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