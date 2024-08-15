function get_shipments_ids(
    solution::Solution, path::Vector{Int}, node::Int, idx::Int, commodity::Commodity
)
    idx == length(path) && return [""]
    next_node = path[idx + 1]
    bins = solution.bins[node, next_node]
    binIdxs = findall(b -> commodity in b.content, bins)
    return string.([bin.idx for bin in bins[binIdxs]])
end

function write_network_design(io::IO, solution::Solution, instance::Instance)
    # push data into a vector 
    data = Vector{Any}(undef, length(NETWORK_DESIGN_COLUMNS))
    data[1] = 1  # route_id
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    for bundle in instance.bundles
        data[2] = bundle.supplier.account  # supplier_account
        data[3] = bundle.customer.account  # customer_account
        path = solution.bundlePaths[bundle.idx]
        for order in bundle.orders
            data[7] = instance.dates[order.deliveryDate]  # delivery_date
            orderCom = unique(order.content)
            timedPath = time_space_projector(TTGraph, TSGraph, path, order)
            for com in orderCom
                data[4] = instance.partNumbers[com.partNumHash]  # part_number
                data[5] = com.size         # packaging
                data[6] = length(findall(x -> x === com, order.content))  # quantity_part_in_route
                for (idx, node) in enumerate(timedPath)
                    data[8] = TSGraph.networkNodes[node].account  # point_account
                    data[9] = idx  # point_index
                    data[10] = instance.dates[TSGraph.timeStep[node]]  # point_date
                    shipments_ids = get_shipments_ids(solution, timedPath, node, idx, com)
                    for id in shipments_ids
                        data[11] = id  # shipment_id
                        # writing data in csv formatted string
                        println(io, join(data, ","))
                    end
                end
            end
            data[1] += 1  # route_id
        end
    end
end

function write_shipment_info(io::IO, solution::Solution, instance::Instance)
    data = Vector{Any}(undef, length(SHIPMENT_INFO_COLUMNS))
    TSGraph = instance.timeSpaceGraph
    for arc in edges(TSGraph.graph)
        data[2] = TSGraph.networkNodes[src(arc)].account  # source_point_account
        data[3] = TSGraph.networkNodes[dst(arc)].account  # destination_point_account
        data[4] = instance.dates[TSGraph.timeStep[src(arc)]]  # point_start_date
        data[5] = instance.dates[TSGraph.timeStep[dst(arc)]]  # point_end_date
        arcData = TSGraph.networkArcs[src(arc), dst(arc)]
        dstData = TSGraph.networkNodes[dst(arc)]
        for bin in solution.bins[src(arc), dst(arc)]
            data[1] = bin.idx  # shipment_id
            data[6] = arcData.type  # type
            data[7] = bin.load  # volume
            data[8] = arcData.unitCost  # unit_cost
            fillingRate = (bin.load / arcData.capacity)
            arcData.isLinear && (data[8] *= fillingRate)
            data[9] = arcData.carbonCost * fillingRate  # carbon_cost
            data[10] = dstData.volumeCost * fillingRate  # platform_cost
            println(io, join(data, ","))
        end
    end
end

# Find the bundle corresponding to the commodity
function find_bundle(instance::Instance, com::Commodity)
    for bundle in instance.bundles
        for order in bundle.orders
            order.hash == com.orderHash && return bundle
        end
    end
end

function write_shipment_content(io::IO, solution::Solution, instance::Instance)
    data = Vector{Any}(undef, length(SHIPMENT_CONTENT_COLUMNS))
    data[1] = 1  # content_id
    for arc in edges(instance.timeSpaceGraph.graph)
        arcData = instance.timeSpaceGraph.networkArcs[src(arc), dst(arc)]
        for bin in solution.bins[src(arc), dst(arc)]
            data[2] = bin.idx  # shipment_id
            contentCom = unique(bin.content)
            for com in contentCom
                data[3] = instance.partNumbers[com.partNumHash]  # part_number
                bundle = find_bundle(instance, com)
                data[4] = bundle.supplier.account  # part_supplier_account
                data[5] = bundle.customer.account  # part_customer_account
                data[6] = length(findall(x -> x === com, bin.content))  # quantity
                data[7] = com.size  # packaging_size
                data[8] = data[6] * data[7]  # volume  
                println(io, join(data, ","))
                data[1] += 1
            end
        end
    end
end

function write_solution(
    solution::Solution, instance::Instance; suffix::String, directory::String
)
    @info "Writing solution to CSV files (suffix: $suffix, directory: $directory)"
    # network design file 
    open("$directory\\network_design_$suffix.csv", "w") do io
        join(io, NETWORK_DESIGN_COLUMNS, ",", "\n")
        write_network_design(io, solution, instance)
    end
    @info "Network design file done"
    # shipment info file
    open("$directory\\shipment_info_$suffix.csv", "w") do io
        join(io, SHIPMENT_INFO_COLUMNS, ",", "\n")
        write_shipment_info(io, solution, instance)
    end
    @info "Shipment info file done"
    # shipment content file
    open("$directory\\shipment_content_$suffix.csv", "w") do io
        join(io, SHIPMENT_CONTENT_COLUMNS, ",", "\n")
        write_shipment_content(io, solution, instance)
    end
    @info "Shipment content file done"
end
