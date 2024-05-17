# This file contains all constants used in the project

# Actual values are Symbol, those list are here for verification
const NODE_TYPES = [:supplier, :plant, :xdock, :iln, :port_l, :port_d]
const COMMON_NODE_TYPES = [:xdock, :iln, :port_l, :port_d]
const ARC_TYPES = [
    :direct, :outsource, :cross_plat, :delivery, :oversea, :port_transport, :shortcut
]
const BP_ARC_TYPES = [:direct, :cross_plat, :delivery, :oversea, :port_transport]
const COMMON_ARC_TYPES = [:cross_plat, :delivery, :oversea, :port_transport]

const EPS = 1e-5
const INFINITY = 1e9
const VOLUME_FACTOR = 100

const LAND_CAPACITY = 7000
const SEA_CAPACITY = 6500

const PERTURBATIONS = [:single_plant, :two_shared_node, :attract_reduce]