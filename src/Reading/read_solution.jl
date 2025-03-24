# Check that the bundle exists in the instance and return it if found
function check_bundle(instance::Instance, row::CSV.Row, anomalyIO::IOStream)
    suppNode = NetworkNode(row.supplier_account, :supplier, "", "", true, 0.0)
    custNode = NetworkNode(row.customer_account, :plant, "", "", true, 0.0)
    bundleHash = hash(suppNode, hash(custNode))
    bundleIdx = findfirst(b -> b.hash == bundleHash, instance.bundles)
    if bundleIdx === nothing
        anomaly_message = "bundle not found in the instance,bundle,solution reading,$(row.supplier_account),$(row.customer_account)"
        println(anomalyIO, anomaly_message)
    else
        return instance.bundles[bundleIdx]
    end
end

# Check that the node exists ins the instance and return it if found
function check_node(instance::Instance, row::CSV.Row, anomalyIO::IOStream)
    nodeHash = hash(row.point_account, hash(Symbol(row.point_type)))
    if haskey(instance.networkGraph.graph, nodeHash)
        return instance.networkGraph.graph[nodeHash]
    else
        anomaly_message = "node not found in the network,node,solution reading,$(row.point_account),"
        println(anomalyIO, anomaly_message)
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
        emptyPathBundles = join(emptyPaths, ", ")
        @warn "Found $(length(emptyPaths)) empty paths for bundles $(emptyPathBundles)"
    end
    missingPointPaths = findall(
        x -> findfirst(y -> y == zero(NetworkNode), x) !== nothing, paths
    )
    if length(missingPointPaths) > 0
        if length(missingPointPaths) > 10
            missingPointBundles = join(missingPointPaths[1:10], ", ")
            @warn "Missing points in $(length(missingPointPaths)) paths for bundles $missingPointBundles ..."
        else
            missingPointBundles = join(missingPointPaths, ", ")
            @warn "Missing points in $(length(missingPointPaths)) paths for bundles $missingPointBundles"
        end
    end
end

# Detect whether the path already has an error or not
function is_path_projectable(path::Vector{NetworkNode}, bundle::Bundle, anomalyIO::IOStream)
    # Is the path empty ?
    if isempty(path)
        anomaly_message = "path is empty,bundle,solution reading,$(bundle.supplier.account),$(bundle.customer.account)"
        println(anomalyIO, anomaly_message)
        return false
    end
    # Is there a missing point ?
    missingNodeIdx = findfirst(x -> x == zero(NetworkNode), path)
    if missingNodeIdx !== nothing
        anomaly_message = "path is missing point number $missingNodeIdx,bundle,solution reading,$(bundle.supplier.account),$(bundle.customer.account)"
        println(anomalyIO, anomaly_message)
        return false
    end
    # Does it start and ends at the right nodes ? (still reversed for now)
    if path[1] != bundle.customer
        anomaly_message = "path does not end at the customer,bundle,solution reading,$(bundle.supplier.account),$(bundle.customer.account)"
        println(anomalyIO, anomaly_message)
        return false
    end
    if path[end] != bundle.supplier
        anomaly_message = "path does not start at the supplier,bundle,solution reading,$(bundle.supplier.account),$(bundle.customer.account)"
        println(anomalyIO, anomaly_message)
        return false
    end
    return true
end

# Find the next node in the projected path if it exists
function find_next_node(TTGraph::TravelTimeGraph, ttNode::Int, node::NetworkNode)
    inNodes = inneighbors(TTGraph.graph, ttNode)
    nextNodeIdx = findfirst(idx -> TTGraph.networkNodes[idx] == node, inNodes)
    nextNodeIdx === nothing && return nothing
    return inNodes[nextNodeIdx]
end

function project_path(
    path::Vector{NetworkNode},
    TTGraph::TravelTimeGraph,
    idx::Int,
    bundle::Bundle,
    anomalyIO::IOStream,
)
    # The travel time path is re-created backward by searching for corresponding nodes
    ttPath = [TTGraph.bundleDst[idx]]
    # Paths in data files are already backwards
    for node in path[2:end]
        # For each node of the path, we search its inneighbor having the same information
        nextNode = find_next_node(TTGraph, ttPath[end], node)
        if nextNode === nothing
            anomaly_message = "path is going out of the time horizon,bundle,solution reading,$(bundle.supplier.account),$(bundle.customer.account)"
            println(anomalyIO, anomaly_message)
            break
        end
        push!(ttPath, nextNode)
    end
    errors = length(ttPath) < length(path)
    return reverse(ttPath), errors
end

# Paths read on the network needs to be projected on the travel-time graph
function project_all_paths(
    paths::Vector{Vector{NetworkNode}}, instance::Instance, anomaly_file::String
)
    TTGraph = instance.travelTimeGraph
    ttPaths = [Int[] for _ in 1:length(paths)]
    open(anomaly_file, "a") do anomalyIO
        for (idx, path) in enumerate(paths)
            bundle = instance.bundles[idx]
            # Paths with errors are skipped
            is_path_projectable(path, bundle, anomalyIO) || continue
            ttPath, errors = project_path(path, TTGraph, idx, bundle, anomalyIO)
            # If not projected completly, leaving it empty, adding it otherwise 
            errors || (ttPaths[idx] = ttPath)
        end
    end
    return ttPaths
end

function read_solution(instance::Instance, solution_file::String, anomaly_file::String)
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
    paths = [NetworkNode[] for _ in 1:length(instance.bundles)]
    # Reading paths
    unknownBundles = 0
    unknownNodes = 0
    open(anomaly_file, "a") do anomalyIO
        for row in csv_reader
            # Check bundle and node existence (warnings if not found)
            bundle = check_bundle(instance, row, anomalyIO)
            if bundle === nothing
                unknownBundles += 1
                continue
            end
            node = check_node(instance, row, anomalyIO)
            if node === nothing
                unknownNodes += 1
                continue
            end
            # Add node to path 
            add_node_to_path!(paths[bundle.idx], node, row.point_number)
        end
    end
    if unknownBundles + unknownNodes > 0
        @warn "$(unknownBundles + unknownNodes) lines were ignored" unknownBundles unknownNodes
    end
    check_paths(paths)
    allPaths = project_all_paths(paths, instance, anomaly_file)
    # Filtering the instance based on anomalies
    idxToKeep = findall(p -> length(p) >= 2, allPaths)
    newBundles, newPaths = instance.bundles[idxToKeep], paths[idxToKeep]
    newBundles = [change_idx(bundle, idx) for (idx, bundle) in enumerate(newBundles)]
    newInstance = Instance(
        instance.networkGraph,
        TravelTimeGraph(instance.networkGraph, newBundles),
        TimeSpaceGraph(instance.networkGraph, instance.timeHorizon),
        newBundles,
        instance.timeHorizon,
        instance.dates,
        instance.partNumbers,
        instance.prices,
    )
    newInstance = add_properties(newInstance, tentative_first_fit, Int[], anomaly_file)
    @info "For $(length(instance.bundles)) bundles, read $(count(p -> length(p) >= 2, paths)) paths, kept $(length(newPaths)) paths and removed $(length(instance.bundles) - length(newPaths)) bundles with errors"
    # Creating and updating solution
    bunPaths = project_all_paths(newPaths, newInstance, anomaly_file)
    solution = Solution(newInstance)
    update_solution!(solution, newInstance, newBundles, bunPaths)
    feasible = is_feasible(newInstance, solution; verbose=true)
    totalCost = compute_cost(newInstance, solution)
    @info "Current solution properties" :feasible = feasible :total_cost = totalCost
    return newInstance, solution
end