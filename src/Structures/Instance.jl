# Instance structure to store problem metadata

# TODO : put travel time and time space graph intot instance

struct Instance
    # Network 
    networkGraph :: NetworkGraph
    # Commodities ordered in bundles
    bundles :: Vector{Bundle}
    # Time Horizon 
    timeHorizon :: Int
    dateHorizon :: Vector{Dates}
end

# Methods

# TODO : maybe a need to create entirely diffrent objects : check that the bundles and all the orders have properties computed
# Computing all objects properties
function add_properties(instance::Instance, bin_packing::Function)
    newBundles = Bundle[add_properties(bundle) for bundle in instance.bundles]
    for bundle in newBundles
        bundle.orders = [add_properties(order, bin_packing) for order in bundle.orders]
    end
    return Instance(instance.networkGraph, newBundles, instance.timeHorizon, instance.dateHorizon)
end

function analyze_instance()
    
end