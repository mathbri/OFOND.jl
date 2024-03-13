# Commodity structure to store corresponding metadata

struct Commodity
    order :: Order        # order of the commodity
    partNumber :: String  # part number of the commodity (still string because need it)
    packageSize :: Int  # size of one package in m3 / 100 
end

# Methods
