# Instance structure to store problem metadata

struct Instance
    # Network 
    networkGraph :: MetaGraph
    # Commodities ordered in bundles
    bundles :: Vector{Bundle}
    # Time Horizon 
    timeHorizon :: Int
    dateHorizon :: Vector{Dates}
end

# Methods

function analyze_instance()
    
end