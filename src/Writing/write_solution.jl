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
    nLines = 0
    routeId = 1
    TTGraph, TSGraph = instance.travelTimeGraph, instance.timeSpaceGraph
    for bundle in instance.bundles
        path = solution.bundlePaths[bundle.idx]
        for order in bundle.orders
            orderCom = unique(order.content)
            timedPath = time_space_projector(TTGraph, TSGraph, path, order)
            for com in orderCom
                quantPartInRoute = length(findall(x -> x === com, order.content))
                comSize = round(com.size / VOLUME_FACTOR; digits=2)
                comWeight = round(com.weight / WEIGHT_FACTOR; digits=2)
                for (idx, node) in enumerate(timedPath)
                    # TODO : all the time is lost in this function, by the findall
                    shipments_ids = get_shipments_ids(solution, timedPath, node, idx, com)
                    for id in shipments_ids
                        # writing data in csv formatted string
                        print(io, routeId, ",") # route_id
                        print(io, bundle.supplier.account, ",") # supplier_account
                        print(io, bundle.customer.account, ",") # customer_account
                        print(io, instance.partNumbers[com.partNumHash], ",") # part_number
                        print(io, comSize, ",") # packaging
                        print(io, comWeight, ",") # weight
                        print(io, quantPartInRoute, ",") # quantity_part_in_route
                        print(io, instance.dates[order.deliveryDate], ",") # delivery_date
                        print(io, TSGraph.networkNodes[node].account, ",") # point_account
                        print(io, idx, ",") # point_index
                        print(io, instance.dates[TSGraph.timeStep[node]], ",") # point_date
                        println(io, id) # shipment_id
                        nLines += 1
                    end
                end
            end
            routeId += 1  # route_id
        end
    end
    return nLines
end

function write_shipment_info(io::IO, solution::Solution, instance::Instance)
    nLines = 0
    TSGraph = instance.timeSpaceGraph
    for arc in edges(TSGraph.graph)
        arcData = TSGraph.networkArcs[src(arc), dst(arc)]
        dstData = TSGraph.networkNodes[dst(arc)]
        for bin in solution.bins[src(arc), dst(arc)]
            fillingRate = (bin.volumeLoad / arcData.volumeCapacity)
            transportCost = arcData.unitCost
            arcData.isLinear && (transportCost *= fillingRate)
            print(io, bin.idx, ",") # shipment_id
            print(io, TSGraph.networkNodes[src(arc)].account, ",") # source_point_account
            print(io, TSGraph.networkNodes[dst(arc)].account, ",") # destination_point_account
            print(io, instance.dates[TSGraph.timeStep[src(arc)]], ",") # point_start_date
            print(io, instance.dates[TSGraph.timeStep[dst(arc)]], ",") # point_end_date
            print(io, arcData.type, ",") # type
            print(io, bin.volumeLoad / VOLUME_FACTOR, ",") # volume
            print(io, bin.weightLoad / WEIGHT_FACTOR, ",") # weight
            # Adding price if available
            srcH = TSGraph.networkNodes[src(arc)].hash
            dstH = TSGraph.networkNodes[dst(arc)].hash
            if haskey(instance.prices, hash(srcH, dstH))
                price = instance.prices[hash(srcH, dstH)]
                print(io, price, ",")
            else
                print(io, ",")
            end
            print(io, transportCost, ",") # unit_cost
            print(io, arcData.carbonCost * fillingRate, ",") # carbon_cost
            println(io, dstData.volumeCost * fillingRate) # platform_cost
            nLines += 1
        end
    end
    return nLines
end

# Construct the bundle finder dictionnary
function create_bundle_finder(instance::Instance)
    bunFinder = Dict{UInt,Int}()
    for bundle in instance.bundles
        for order in bundle.orders
            bunFinder[order.hash] = bundle.idx
        end
    end
    return bunFinder
end

function write_shipment_content(io::IO, solution::Solution, instance::Instance)
    nLines = 0
    # order hash to bundle idx dict to efficiently recover bundle of commodities
    bundleFinder = create_bundle_finder(instance)
    contentId = 1  # content_id
    # Efficient iteration over sparse matrix
    allBins = nonzeros(solution.bins)
    for dst in 1:size(solution.bins, 2)
        for i in nzrange(solution.bins, dst)
            # allBins[i] get solution.bins[src, dst] with src = rowvals(solution.bins)[i]
            for bin in allBins[i]
                contentCom = unique(bin.content)
                for com in contentCom
                    bunIdx = bundleFinder[com.orderHash]
                    bundle = instance.bundles[bunIdx]
                    print(io, contentId, ",") # content_id
                    print(io, bin.idx, ",") # shipment_id
                    print(io, instance.partNumbers[com.partNumHash], ",") # part_number
                    print(io, bundle.supplier.account, ",") # part_supplier_account
                    print(io, bundle.customer.account, ",") # part_customer_account
                    quantity = length(findall(x -> x === com, bin.content))
                    print(io, quantity, ",") # quantity
                    print(io, com.size / VOLUME_FACTOR, ",") # packaging_size
                    print(io, com.weight / WEIGHT_FACTOR, ",") # pack_weight
                    println(io, quantity * com.size / VOLUME_FACTOR) # volume
                    print(io, quantity * com.weight / WEIGHT_FACTOR, ",") # weight
                    contentId += 1
                    nLines += 1
                end
            end
        end
    end
    return nLines
end

function write_solution(
    solution::Solution, instance::Instance; suffix::String, directory::String
)
    @info "Writing solution to CSV files (suffix: $suffix, directory: $directory)"
    # network design file 
    nLines = 0
    open(joinpath(directory, "network_design_$suffix.csv"), "w") do io
        println(io, join(NETWORK_DESIGN_COLUMNS, ","))
        nLines = write_network_design(io, solution, instance)
    end
    @info "Network design file done ($nLines lines x $(length(NETWORK_DESIGN_COLUMNS)) columns)"
    # shipment info file
    open(joinpath(directory, "shipment_info_$suffix.csv"), "w") do io
        println(io, join(SHIPMENT_INFO_COLUMNS, ","))
        nLines = write_shipment_info(io, solution, instance)
    end
    @info "Shipment info file done ($nLines lines x $(length(SHIPMENT_INFO_COLUMNS)) columns)"
    # shipment content file
    open(joinpath(directory, "shipment_content_$suffix.csv"), "w") do io
        println(io, join(SHIPMENT_CONTENT_COLUMNS, ","))
        nLines = write_shipment_content(io, solution, instance)
    end
    @info "Shipment content file done ($nLines lines x $(length(SHIPMENT_CONTENT_COLUMNS)) columns)"
end
