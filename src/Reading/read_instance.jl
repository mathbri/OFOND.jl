# File containing all functions to read an instance

# TODO : gather anomalies in anomaly file

function are_node_data_missing(row::CSV.Row)
    return ismissing(row.point_account) ||
           ismissing(row.point_type) ||
           ismissing(row.point_m3_cost)
end

function read_node!(counts::Dict{Symbol,Int}, row::CSV.Row)
    nodeType = Symbol(row.point_type)
    haskey(counts, nodeType) && (counts[nodeType] += 1)
    account, country, continent = promote(
        row.point_account, row.point_country, row.point_continent
    )
    return NetworkNode(
        account,
        nodeType,
        country,
        continent,
        nodeType in COMMON_NODE_TYPES,
        row.point_m3_cost,
    )
end

function read_and_add_nodes!(
    network::NetworkGraph, node_file::String, anomaly_file::String; verbose::Bool=false
)
    start = time()
    counts = Dict([(nodeType, 0) for nodeType in OFOND.NODE_TYPES])
    # Reading .csv file
    csv_reader = CSV.File(
        node_file; types=Dict("point_account" => String, "point_type" => String)
    )
    @info "Reading nodes from CSV file $(basename(node_file)) ($(length(csv_reader)) lines)"
    ignored = Dict(:same_node => 0, :unknown_type => 0, :missing_data => 0)
    open(anomaly_file, "a") do anomalyIO
        for row in csv_reader
            if are_node_data_missing(row)
                ignored[:missing_data] += 1
                anomaly_message = "missing data for the node,node,instance reading,$(row.point_account),"
                println(anomalyIO, anomaly_message)
                continue
            end
            node = read_node!(counts, row)
            added, ignore_type = add_node!(network, node; verbose=verbose)
            if !added
                ignored[ignore_type] += 1
                anomaly_message = if ignore_type == :same_node
                    "node with same account and type already in the network,node,instance reading,$(row.point_account),"
                elseif ignore_type == :unknown_type
                    "node with unknown type,node,instance reading,$(row.point_account),"
                end
                println(anomalyIO, anomaly_message)
            end
        end
    end
    ignoredStr = join(pairs(ignored), ", ")
    timeTaken = round(time() - start; digits=1)
    @info "Read $(nv(network.graph)) nodes : $counts" :ignored = ignoredStr :time =
        timeTaken
end

function are_leg_data_missing(row::CSV.Row)
    return ismissing(row.src_account) ||
           ismissing(row.dst_account) ||
           ismissing(row.src_type) ||
           ismissing(row.dst_type) ||
           ismissing(row.leg_type) ||
           ismissing(row.distance) ||
           ismissing(row.travel_time) ||
           ismissing(row.shipment_cost) ||
           ismissing(row.capacity) ||
           ismissing(row.carbon_cost)
end

function src_dst_hash(row::CSV.Row)
    return hash(row.src_account, hash(Symbol(row.src_type))),
    hash(row.dst_account, hash(Symbol(row.dst_type)))
end

function is_common_arc(row::CSV.Row)
    return Symbol(row.leg_type) in COMMON_ARC_TYPES
end

function is_current(row::CSV.Row)
    try
        if row.type_simu == "e"
            return true
        end
    catch e
        # Doing nothing if the column isn't here
    end
    return false
end

function add_leg_price!(tariffNames::Dict{UInt,String}, src::UInt, dst::UInt, row::CSV.Row)
    try
        tariffNames[hash(src, dst)] = row.tarif_name
    catch e
        # Doing nothing if the column isn't here
    end
end

function read_leg!(counts::Dict{Symbol,Int}, row::CSV.Row, isCommon::Bool)
    arcType = Symbol(row.leg_type)
    haskey(counts, arcType) && (counts[arcType] += 1)
    if row.shipment_cost > 1e6
        @warn "Verye huge cost : Shipment cost exceeds 1M€ per unit of shipment" :arcType =
            arcType :row = row
    end
    volumeCapacity = min(round(Int, row.capacity * VOLUME_FACTOR), LAND_CAPACITY)
    weightCapacity = WEIGHT_CAPACITY
    try
        weightCapacity = min(round(Int, row.capacity_ton * WEIGHT_FACTOR), WEIGHT_CAPACITY)
    catch e
        # Doing nothing if the column isn't here
    end
    return NetworkArc(
        arcType,
        row.distance,
        floor(Int, row.travel_time + 0.5),
        isCommon,
        min(row.shipment_cost, 3e5),
        row.is_linear,
        row.carbon_cost,
        volumeCapacity,
        weightCapacity,
        !is_current(row),
    )
end

function read_and_add_legs!(
    network::NetworkGraph, leg_file::String, anomaly_file::String; verbose::Bool=false
)
    start = time()
    counts = Dict([(arcType, 0) for arcType in OFOND.ARC_TYPES])
    # Reading .csv file
    columns = ["src_account", "dst_account", "src_type", "dst_type", "leg_type"]
    csv_reader = CSV.File(leg_file; types=Dict([(column, String) for column in columns]))
    @info "Reading legs from CSV file $(basename(leg_file)) ($(length(csv_reader)) lines)"
    ignored = Dict(
        :same_arc => 0,
        :unknown_type => 0,
        :unknown_source => 0,
        :unknown_dest => 0,
        :missing_data => 0,
    )
    tariffNames = Dict{UInt,String}()
    # println(csv_reader[1])
    minCost, maxCost, meanCost = INFINITY, 0.0, 0.0
    open(anomaly_file, "a") do anomalyIO
        for row in csv_reader
            if are_leg_data_missing(row)
                ignored[:missing_data] += 1
                anomaly_message = "missing data for the leg,leg,instance reading,$(row.src_account),$(row.dst_account)"
                println(anomalyIO, anomaly_message)
                continue
            end
            src, dst = src_dst_hash(row)
            # Checking if there is a price name
            add_leg_price!(tariffNames, src, dst, row)
            arc = read_leg!(counts, row, is_common_arc(row))
            added, ignore_type = add_arc!(network, src, dst, arc; verbose=verbose)
            if !added
                ignored[ignore_type] += 1
                anomaly_message = if ignore_type == :same_arc
                    "leg with same source and destination already in the network,leg,instance reading,$(row.src_account),$(row.dst_account)"
                elseif ignore_type == :unknown_type
                    "leg with unknown type,leg,instance reading,$(row.src_account),$(row.dst_account)"
                elseif ignore_type == :unknown_source
                    "leg with unknown source,leg,instance reading,$(row.src_account),$(row.dst_account)"
                elseif ignore_type == :unknown_dest
                    "leg with unknown destination,leg,instance reading,$(row.src_account),$(row.dst_account)"
                end
                println(anomalyIO, anomaly_message)
            else
                minCost = min(minCost, row.shipment_cost)
                maxCost = max(maxCost, row.shipment_cost)
                meanCost += row.shipment_cost
            end
        end
    end
    ignoredStr = join(pairs(ignored), ", ")
    timeTaken = round(time() - start; digits=1)
    @info "Read $(ne(network.graph)) legs : $counts" :ignored = ignoredStr :time = timeTaken
    println("Tariffs read : $(length(tariffNames))")
    println("Min arc cost : $minCost")
    println("Max arc cost : $maxCost")
    println("Mean arc cost : $(meanCost / ne(network.graph))")
    return tariffNames
end

function are_commodity_data_missing(row::CSV.Row)
    return ismissing(row.supplier_account) ||
           ismissing(row.customer_account) ||
           ismissing(row.delivery_time_step) ||
           ismissing(row.size) ||
           ismissing(row.delivery_date) ||
           ismissing(row.part_number) ||
           ismissing(row.quantity) ||
           ismissing(row.lead_time_cost)
end

function bundle_hash(row::CSV.Row)
    return hash(row.supplier_account, hash(row.customer_account))
end

function order_hash(row::CSV.Row)
    return hash(row.delivery_time_step + 1, bundle_hash(row))
end

function com_size(row::CSV.Row)
    baseSize = min(round(Int, max(1, row.size * VOLUME_FACTOR)), SEA_CAPACITY)
    return baseSize
end

function com_weight(row::CSV.Row)
    if row.weight_per_emb === missing
        return 1
    end
    weight = row.weight_per_emb * WEIGHT_FACTOR
    while weight > WEIGHT_CAPACITY
        weight = weight / WEIGHT_FACTOR
    end
    return round(Int, max(1, weight))
end

function get_bundle!(
    bundles::Dict{UInt,Bundle}, row::CSV.Row, network::NetworkGraph, anomalyIO::IOStream
)
    # Get supplier and customer nodes
    if !haskey(network.graph, hash(row.supplier_account, hash(:supplier)))
        @warn "Supplier unknown in the network" :supplier = row.supplier_account :row = row
        anomaly_message = "commodity supplier unknown in the network,commodity,instance reading,$(row.supplier_account),$(row.customer_account)"
        println(anomalyIO, anomaly_message)
    elseif !haskey(network.graph, hash(row.customer_account, hash(:plant)))
        @warn "Customer unknown in the network" :customer = row.customer_account :row = row
        anomaly_message = "commodity customer unknown in the network,commodity,instance reading,$(row.supplier_account),$(row.customer_account)"
        println(anomalyIO, anomaly_message)
    else
        supplierNode = network.graph[hash(row.supplier_account, hash(:supplier))]
        customerNode = network.graph[hash(row.customer_account, hash(:plant))]
        return get!(
            bundles,
            bundle_hash(row),
            Bundle(supplierNode, customerNode, length(bundles) + 1),
        )
    end
end

# Vectors starts at index 0 in Python so adding 1 to get the right index in Julia
function get_order!(orders::Dict{UInt,Order}, row::CSV.Row, bundle::Bundle)
    return get!(orders, order_hash(row), Order(bundle, row.delivery_time_step + 1))
end

function add_date!(dateHorizon::Vector{String}, row::CSV.Row)
    dateIdx = row.delivery_time_step + 1
    if length(dateHorizon) < dateIdx
        append!(dateHorizon, ["" for _ in 1:(dateIdx - length(dateHorizon))])
    end
    if dateHorizon[dateIdx] == ""
        dateHorizon[dateIdx] = row.delivery_date
    end
end

function read_commodities(
    networkGraph::NetworkGraph, commodities_file::String, anomaly_file::String
)
    start = time()
    orders, bundles = Dict{UInt,Order}(), Dict{UInt,Bundle}()
    dates, partNums = Vector{String}(), Dict{UInt,String}()
    comCount, comUnique = 0, 0
    # Reading .csv file
    csv_reader = CSV.File(
        commodities_file;
        types=Dict(
            "supplier_account" => String,
            "customer_account" => String,
            "delivery_date" => String,
        ),
    )
    @info "Reading commodity orders from CSV file $(basename(commodities_file)) ($(length(csv_reader)) lines)"
    # Creating objects : each line is a commodity order
    # println(csv_reader[1])
    firstWeek = Date(Dates.now())
    lastWeek = Date(Dates.now())
    ignored = Dict(:unknown_bundle => 0, :missing_data => 0)
    open(anomaly_file, "a") do anomalyIO
        for (i, row) in enumerate(csv_reader)
            if are_commodity_data_missing(row)
                ignored[:missing_data] += 1
                anomaly_message = "missing data for the commodity,commodity,instance reading,$(row.supplier_account),$(row.customer_account)"
                println(anomalyIO, anomaly_message)
                continue
            end
            # if row.delivery_time_step + 1 >= 7
            #     continue
            # end
            # Getting bundle, order and commodity data
            bundle = get_bundle!(bundles, row, networkGraph, anomalyIO)
            if bundle === nothing
                ignored[:unknown_bundle] += 1
                continue
            end
            order = get_order!(orders, row, bundle)
            # If the order is new (no commodities) we have to add it to the bundle
            length(order.content) == 0 && push!(bundle.orders, order)
            # Creating (and Duplicating) commodity
            partNumHash = hash(row.part_number)
            partNums[partNumHash] = row.part_number
            commodity = Commodity(
                order.hash, partNumHash, com_size(row), com_weight(row), row.lead_time_cost
            )
            append!(order.content, [commodity for _ in 1:(row.quantity)])
            comCount += row.quantity
            comUnique += 1
            # Is it a new time step ?
            add_date!(dates, row)
            if Date(DateTime(row.delivery_date[1:10])) < firstWeek
                firstWeek = Date(DateTime(row.delivery_date[1:10]))
            elseif Date(DateTime(row.delivery_date[1:10])) > lastWeek
                lastWeek = Date(DateTime(row.delivery_date[1:10]))
            end
        end
    end
    # Transforming dictionnaries into vectors (sorting the vector so that the idx field correspond to the actual idx in the vector)
    bundleVector = sort(collect(values(bundles)); by=bundle -> bundle.idx)
    ignoreStr = join(pairs(ignored), ", ")
    timeTaken = round(time() - start; digits=1)
    @info "Read $(length(bundles)) bundles, $(length(orders)) orders and $comCount commodities ($comUnique without quantities) on a $(length(dates)) steps time horizon" :ignored =
        ignoreStr :time = timeTaken
    timeFrame = lastWeek - firstWeek
    timeFrameDates = Dates.Day(Dates.Week(length(dates)))
    if abs(timeFrame - timeFrameDates) > Dates.Day(7)
        @warn "Time frame computed with dates don't match the number of weeks in the time horizon, this may cause an error" :dates =
            timeFrameDates :timeFrame = timeFrame
        # println("Collected dates : $dates")
        # println("First week : $firstWeek")
        # println("Last week : $lastWeek")
        # println("Time frame : $timeFrame")
        # knownDates = [Date(DateTime(dateString[1:10])) for dateString in dates]
        # println(knownDates)
        # sort!(knownDates)
        # println(knownDates)
        # for (i, knownDate) in enumerate(knownDates)
        #     println("\nDate $i : $knownDate")
        #     println("Date $(i+1) : $(knownDates[i+1])")
        #     println("Delay between them : $(knownDate + Dates.Week(1) - knownDates[i + 1])")
        #     if knownDate + Dates.Week(1) != knownDates[i + 1]
        #         println("Added date : $(knownDate + Dates.Week(1))")
        #         push!(dates, string(knownDate + Dates.Week(1)))
        #     end
        # end
        # throw(ErrorException("Horizon reconstructed"))
    end
    return bundleVector, dates, partNums
end

function read_instance(
    node_file::String, leg_file::String, commodities_file::String, anomaly_file::String
)
    networkGraph = NetworkGraph()
    read_and_add_nodes!(networkGraph, node_file, anomaly_file)
    tariffs = read_and_add_legs!(networkGraph, leg_file, anomaly_file)
    # Adding general properties 
    seaTime, seaNumber, maxLeg = 0, 0, 0
    netGraph = networkGraph.graph
    trueDirects = 0
    for (srcHash, dstHash) in edge_labels(netGraph)
        if netGraph[srcHash, dstHash].type == :oversea
            seaTime += netGraph[srcHash, dstHash].travelTime
            seaNumber += 1
        elseif netGraph[srcHash, dstHash].type == :direct
            if netGraph[srcHash].type == :supplier && netGraph[dstHash].type == :plant
                trueDirects += 1
            else
                println(netGraph[srcHash])
                println(netGraph[dstHash])
                println(netGraph[srcHash, dstHash])
                throw(ErrorException("False direct"))
            end
        end
        maxLeg = max(maxLeg, netGraph[srcHash, dstHash].travelTime)
    end
    meanOverseaTime = seaNumber == 0 ? 0 : round(Int, seaTime / seaNumber)
    netGraph[][:meanOverseaTime] = meanOverseaTime
    netGraph[][:maxLeg] = maxLeg
    println("True directs : $(trueDirects)")
    bundles, dates, partNums = read_commodities(
        networkGraph, commodities_file, anomaly_file
    )
    horizon = length(dates)
    if netGraph[][:maxLeg] > length(dates)
        @warn "The longest leg is $(netGraph[][:maxLeg]) steps long, which is longer than the time horizon ($(length(dates)) steps), the new horizon will be $(netGraph[][:maxLeg] + 1) steps"
        anomaly_message = "longest leg is $(netGraph[][:maxLeg]) steps long but horizon is $(length(dates)) steps long,horizon,,"
        open(anomaly_file, "a") do io
            println(io, anomaly_message)
        end
        horizon = netGraph[][:maxLeg] + 1
        lastWeek = Date(DateTime(dates[end][1:10]))
        for i in 1:(horizon - length(dates))
            push!(dates, string(lastWeek + Dates.Week(i)))
        end
    end
    return Instance(
        networkGraph,
        TravelTimeGraph(),
        TimeSpaceGraph(),
        bundles,
        horizon,
        dates,
        partNums,
        tariffs,
    )
end