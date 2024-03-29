# Utility functions

# These functions are made to be used across the whole project and are not specifically made for a stucture or specific algorithm

function get_path_nodes(path::Vector{Edge})
    return vcat([src(e) for e in path],  [dst(path[1])])
end