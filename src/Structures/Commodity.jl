# Commodity structure to store corresponding metadata

# TODO : transform hashs into shallow copy of objects for easier usage
struct Commodity
    supplier :: UInt      # supplier of the commodity
    customer :: UInt      # customer of the commodity
    partNumber :: String  # part number of the commodity (still string because need it)
    packageSize :: Int16  # size of one package in m3 / 100 
end

# Methods
