# Instance structure to store problem metadata

struct Instance
    # Parameters
    parameters :: Parameters
    # Network 
    networkGraph :: MetaGraph
    # Commodities
    commodities :: Dict{UInt, Commodity}
    orders :: Dict{UInt, Order}
    bundles :: Dict{UInt, Bundle}
    # Time Horizon 
    timeHorizon :: Int
    dateHorizon :: Vector{Dates}

    Instance(parameters, nodes, legs, commodities, orders, timeHorizon) = new(
        parameters, nodes, legs, commodities, orders, timeHorizon, get_date_to_index(timeHorizon)
    )
end

# Methods

function analyze_instance()
    
end