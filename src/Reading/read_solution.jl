# TODO : maybe do some bin packing improvement to obtain the best current solution for fair comparison ?
# TODO : check feasibility ?

# Check that the bundle exists in the instance and return it if found
function check_bundle(instance::Instance, row::CSV.Row)
    suppNode = NetworkNode(row.supplier_account, :supplier, "", LLA(0, 0), "", "", true, 0)
    custNode = NetworkNode(row.customer_account, :plant, "", LLA(0, 0), "", "", true, 0)
    bundleHash = hash(suppNode, hash(custNode))
    bundle = findfirst(b -> b.hash == bundleHash, instance.bundles)
    if bundle === nothing
        @warn "Bundle unknown in the instance" :bundle = bundleHash :row = row
    else
        return bundle
    end
end

# Check that the node exists ins the instance and return it if found
function check_node(instance::Instance, row::CSV.Row)
    nodeHash = hash(row.point_account, hash(row.point_type))
    if haskey(instance.networkGraph.graph, nodeHash)
        return instance.networkGraph.graph[nodeHash]
    else
        @warn "Node unknown in the network" :node = nodeHash :row = row
    end
end

# Add the node to the path, updating path length if needed
function add_node_to_path!(path::Vector{NetworkNode}, node::NetworkNode, idx::Int)
    if idx > length(path)
        for _ in 1:(idx - length(path))
            push!(path, zero(NetworkNode))
        end
    end
    return path[idx] = node
end

# Detect errors in paths
function check_paths(paths::Vector{Vector{NetworkNode}})
    emptyPaths = findall(x -> length(x) == 0, paths)
    if length(emptyPaths) > 0
        @warn "Found $(length(emptyPaths)) empty paths for bundles $(emptyPaths)"
    end
    missingPointPaths = findall(
        x -> length(findfirst(y -> y == zero(NetworkNode), x)) !== nothing, paths
    )
    if length(missingPointPaths) > 0
        @warn "Missing points in $(length(missingPointPaths)) paths for bundles $(missingPointPaths)"
    end
end

# Detect whether the path already has an error or not
function is_path_projectable(path::Vector{NetworkNode})
    missingPoints = findall(x -> x == zero(NetworkNode), path)
    return (length(path) > 0) && (length(missingPoints) == 0)
end

# TODO : test from here on

# Find the next node in the projected path if it exists
function find_next_node(TTGraph::TravelTimeGraph, ttNode::Int, node::NetworkNode)
    return findfirst(idx -> TTGraph.networkNodes == node, inneighors(TTGraph.graph, ttNode))
end

function project_path(path::Vector{NetworkNode}, TTGraph::TravelTimeGraph, idx::Int)
    # The travel time path is re-created backward by searching for corresponding nodes
    ttPath = [TTGraph.bundleDst[idx]]
    for node in reverse(path[1:(end - 1)])
        # For each node of the path, we search its inneighbor having the same information
        nextNode = find_next_node(TTGraph, ttPath[end], node)
        if nextNode === nothing
            @warn "Next node not found, path not projectable for bundle $(idx)" :node = node :ttNode = ttPath[end]
            break
        end
        push!(ttPath, nextNode)
    end
    errors = length(ttPath) < length(path)
    return reverse(ttPath), errors
end

# Paths read on the network needs to be projected on the travel-time graph
function project_all_paths(paths::Vector{Vector{NetworkNode}}, TTGraph::TravelTimeGraph)
    ttPaths = [Int[] for _ in 1:length(paths)]
    for (idx, path) in enumerate(paths)
        # Paths with errors are skipped
        is_path_projectable(path) || continue
        ttPath, errors = project_path(path, TTGraph, idx)
        # If not projected completly, leaving it empty, adding it otherwise 
        errors || (ttPaths[idx] = ttPath)
    end
    return ttPaths
end

# Repair paths by putting direct paths for bundles with errors
function repair_paths!(paths::Vector{Vector{Int}}, instance::Instance)
    TTGraph = instance.travelTimeGraph
    for (idx, path) in enumerate(paths)
        if length(path) == 0
            suppNode, custNode = TTGraph.bundleSrc[idx], TTGraph.bundleDst[idx]
            # Computing shortest path
            shortestPath, pathCost = shortest_path(TTGraph, suppNode, custNode)
            append!(path, shortestPath)
        end
    end
end

function read_solution(instance::Instance, solution_file::String)
    # Reading .csv file
    csv_reader = CSV.File(
        solution_file;
        types=Dict(
            "supplier_account" => String,
            "customer_account" => String,
            "point_account" => String,
            "point_number" => Int,
        ),
    )
    @info "Reading solution from CSV file $(basename(solution_file)) ($(length(csv_reader)) lines)"
    paths = [Int[] for _ in 1:length(instance.bundles)]
    # Reading paths
    for row in csv_reader
        # Check bundle and node existence (warnings if not found)
        bundle = check_bundle(instance, row)
        node = check_node(instance, row)
        (bundle === nothing || node === nothing) && continue
        # Add node to path 
        add_node_to_path!(paths[bundle.idx], node, row.point_number)
    end
    @info "Read $(length(paths)) paths"
    check_paths(paths)
    @info "Projecting paths on the travel-time graph"
    allPaths = project_all_paths(paths, instance.travelTimeGraph)
    check_paths(allPaths)
    @info "Repairing paths for bundles with errors"
    repair_paths!(allPaths, instance)
    # Creating and updating solution
    solution = Solution(instance)
    update_solution!(solution, instance, instance.bundles, allPaths)
    return solution
end