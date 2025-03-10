# File containing all functions to read an instance

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

function read_and_add_nodes!(network::NetworkGraph, node_file::String)
    counts = Dict([(nodeType, 0) for nodeType in OFOND.NODE_TYPES])
    # Reading .csv file
    csv_reader = CSV.File(
        node_file; types=Dict("point_account" => String, "point_type" => String)
    )
    @info "Reading nodes from CSV file $(basename(node_file)) ($(length(csv_reader)) lines)"
    ignored = Dict(:same_node => 0, :unknown_type => 0)
    for row in csv_reader
        node = read_node!(counts, row)
        added, ignore_type = add_node!(network, node)
        added || (ignored[ignore_type] += 1)
        if node.volumeCost < EPS && node.type in [:xdock, :iln]
            # println(row)
            # println(node)
            # @error "No volume cost on this platform"
            # throw(ErrorException("No volume cost on this platform"))
        end
    end
    ignoredStr = join(pairs(ignored), ", ")
    @info "Read $(nv(network.graph)) nodes : $counts" :ignored = ignoredStr
end

function src_dst_hash(row::CSV.Row)
    @assert !ismissing(row.src_account)
    @assert !ismissing(row.dst_account)
    @assert !ismissing(row.src_type)
    @assert !ismissing(row.dst_type)
    return hash(row.src_account, hash(Symbol(row.src_type))),
    hash(row.dst_account, hash(Symbol(row.dst_type)))
end

function is_common_arc(row::CSV.Row)
    return Symbol(row.src_type) in COMMON_NODE_TYPES &&
           Symbol(row.dst_type) in COMMON_NODE_TYPES
end

function read_leg!(counts::Dict{Symbol,Int}, row::CSV.Row, isCommon::Bool)
    @assert !ismissing(row.leg_type)
    arcType = Symbol(row.leg_type)
    haskey(counts, arcType) && (counts[arcType] += 1)
    if ismissing(row.distance)
        println(row)
    end
    @assert !ismissing(row.distance)
    @assert !ismissing(row.travel_time)
    @assert !ismissing(row.shipment_cost)
    @assert !ismissing(row.carbon_cost)
    @assert !ismissing(row.capacity)
    if row.shipment_cost > 1e6
        @warn "Verye huge cost : Shipment cost exceeds 1M€ per unit of shipment" :arcType =
            arcType :row = row
    end
    return NetworkArc(
        arcType,
        row.distance,
        floor(Int, row.travel_time),
        # min(floor(Int, row.travel_time), 7),
        isCommon,
        min(row.shipment_cost, 1.5e4),
        row.is_linear,
        row.carbon_cost,
        row.capacity * VOLUME_FACTOR,
        WEIGHT_CAPACITY,
    )
end

function read_and_add_legs!(
    network::NetworkGraph, leg_file::String; ignoreCurrent::Bool=false
)
    counts = Dict([(arcType, 0) for arcType in OFOND.ARC_TYPES])
    # Reading .csv file
    columns = ["src_account", "dst_account", "src_type", "dst_type", "leg_type"]
    csv_reader = CSV.File(leg_file; types=Dict([(column, String) for column in columns]))
    @info "Reading legs from CSV file $(basename(leg_file)) ($(length(csv_reader)) lines)"
    ignored = Dict(
        :same_arc => 0, :unknown_type => 0, :unknown_source => 0, :unknown_dest => 0
    )
    tariffNames = Dict{UInt,String}()
    # println(csv_reader[1])
    for row in csv_reader
        # Checking if we should ignore this arc
        if ignoreCurrent
            try
                if row.type_simu == "e"
                    continue
                end
            catch e
                # Doing nothing if the column isn't here
            end
        end
        src, dst = src_dst_hash(row)
        # Checking if there is a price name
        try
            tariffNames[hash(src, dst)] = row.tariff_name
        catch e
            # Doing nothing if the column isn't here
        end
        arc = read_leg!(counts, row, is_common_arc(row))
        added, ignore_type = add_arc!(network, src, dst, arc)
        added || (ignored[ignore_type] += 1)
    end
    ignoredStr = join(pairs(ignored), ", ")
    @info "Read $(ne(network.graph)) legs : $counts" :ignored = ignoredStr
    return tariffNames
end

function bundle_hash(row::CSV.Row)
    return hash(row.supplier_account, hash(row.customer_account))
end

function order_hash(row::CSV.Row)
    return hash(row.delivery_time_step + 1, bundle_hash(row))
end

function com_size(row::CSV.Row)
    return round(Int, max(1, row.size * VOLUME_FACTOR))
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

function get_bundle!(bundles::Dict{UInt,Bundle}, row::CSV.Row, network::NetworkGraph)
    # Get supplier and customer nodes
    if !haskey(network.graph, hash(row.supplier_account, hash(:supplier)))
        @warn "Supplier unknown in the network" :supplier = row.supplier_account :row = row
    elseif !haskey(network.graph, hash(row.customer_account, hash(:plant)))
        @warn "Customer unknown in the network" :customer = row.customer_account :row = row
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

function read_commodities(networkGraph::NetworkGraph, commodities_file::String)
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
    firstWeek = Date(DateTime(csv_reader[1].delivery_date[1:10]))
    lastWeek = Date(DateTime(csv_reader[1].delivery_date[1:10]))
    for (i, row) in enumerate(csv_reader)
        # Getting bundle, order and commodity data
        bundle = get_bundle!(bundles, row, networkGraph)
        bundle === nothing && continue
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
    # Transforming dictionnaries into vectors (sorting the vector so that the idx field correspond to the actual idx in the vector)
    bundleVector = sort(collect(values(bundles)); by=bundle -> bundle.idx)
    @info "Read $(length(bundles)) bundles, $(length(orders)) orders and $comCount commodities ($comUnique without quantities) on a $(length(dates)) steps time horizon"
    timeFrame = lastWeek - firstWeek
    timeFrameDates = Dates.Day(Dates.Week(length(dates)))
    if abs(timeFrame - timeFrameDates) > Dates.Day(7)
        @warn "Time frame computed with dates don't match the number of weeks in the time horizon, this may cause an error" :dates =
            timeFrameDates :timeFrame = timeFrame
    end
    return bundleVector, dates, partNums
end

function read_instance(
    node_file::String, leg_file::String, commodities_file::String; ignoreCurrent::Bool=false
)
    networkGraph = NetworkGraph()
    read_and_add_nodes!(networkGraph, node_file)
    tariffs = read_and_add_legs!(networkGraph, leg_file; ignoreCurrent=ignoreCurrent)
    add_global_leg_info!(networkGraph)
    bundles, dates, partNums = read_commodities(networkGraph, commodities_file)
    if networkGraph.graph[]["maxLeg"] > length(dates)
        maxLeg = networkGraph.graph[]["maxLeg"]
        horizon = length(dates)
        @error "The longest leg is $(maxLeg) steps long, which is longer than the time horizon ($(horizon) steps), this may cause an error"
    end
    return Instance(
        networkGraph,
        TravelTimeGraph(),
        TimeSpaceGraph(),
        bundles,
        length(dates),
        dates,
        partNums,
        tariffs,
    )
end