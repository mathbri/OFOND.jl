# This file contains all constants used in the project

const SUPPLIER, PLANT, PLATFORM = hash("supplier"), hash("plant"), hash("platform")
const PORT_L, PORT_D = hash("port-l"), hash("port-d")

const DIRECT, OUTSOURCE, CROSS_PLAT, DELIVERY = hash("direct"), hash("outsource"), hash("cross-plat"), hash("delivery")
const OVERSEA, PORT_TRANSPORT = hash("oversea"), hash("port-transport")

const TYPE_TO_STRING = Dict{UInt, String}(
    SUPPLIER => "Supplier", PLANT => "Plant", PLATFORM => "Platform", PORT_L => "Port-L", PORT_D => "Port-D", 
    DIRECT => "Direct", OUTSOURCE => "Outsource", CROSS_PLAT => "Cross-Plat", OVERSEA => "Oversea", 
    PORT_TRANSPORT => "Port-Transport", DELIVERY => "Delivery"
) 

const EPS = 1e-5
const SHORTCUT = hash("Shortcut")