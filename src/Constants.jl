# This file contains all constants used in the project

# Actual values are Symbol, those list are here for verification
const NODE_TYPES = [:supplier, :plant, :xdock, :iln, :port_l, :port_d]
const COMMON_NODE_TYPES = [:xdock, :iln, :port_l, :port_d]
const ARC_TYPES = [:direct, :outsource, :cross_plat, :delivery, :oversea, :port_transport, :shortcut]

const EPS = 1e-5
const INFINITY = 1e9