# Bin structure used in for bin-packing

# TODO : Changing form mutable to immutable could be a way to improve efficiency

mutable struct Bin
    idx::Int                    # index for output purposes
    volumeCapacity::Int         # space left in the bin
    volumeLoad::Int             # space used in the bin
    weightCapacity::Int         # weight left in the bin
    weightLoad::Int             # weight used in the bin
    content::Vector{Commodity}  # which commodity is in the bin

    function Bin(capaV::Int, loadV::Int, capaW::Int, loadW::Int, content::Vector{Commodity})
        @assert capaV >= 0 && loadV >= 0 && capaW >= 0 && loadW >= 0
        binIdx = round(Int, rand() * typemax(Int))
        return new(binIdx, capaV, loadV, capaW, loadW, content)
    end
end

function Bin(volumeCapacity::Int, weightCapacity::Int)
    return Bin(volumeCapacity, 0, weightCapacity, 0, Vector{Commodity}())
end

function Bin(volumeCapacity::Int, weightCapacity::Int, commodity::Commodity)
    if commodity.size > volumeCapacity || commodity.weight > weightCapacity
        return Bin(0, volumeCapacity, 0, weightCapacity, [commodity])
    end
    capaV = max(0, volumeCapacity - commodity.size)
    capaW = max(0, weightCapacity - commodity.weight)
    return Bin(capaV, commodity.size, capaW, commodity.weight, [commodity])
end

# Methods 

function Base.:(==)(bin1::Bin, bin2::Bin)
    return bin1.volumeCapacity == bin2.volumeCapacity &&
           bin1.volumeLoad == bin2.volumeLoad &&
           bin1.weightCapacity == bin2.weightCapacity &&
           bin1.weightLoad == bin2.weightLoad &&
           bin1.content == bin2.content
end

function Base.show(io::IO, bin::Bin)
    return print(
        io,
        "Bin($(bin.volumeCapacity), $(bin.volumeLoad), $(bin.weightCapacity), $(bin.weightLoad), $(bin.content))",
    )
end

function add!(bin::Bin, commodity::Commodity)
    if bin.volumeCapacity >= commodity.size && bin.weightCapacity >= commodity.weight
        push!(bin.content, commodity)
        bin.volumeCapacity -= commodity.size
        bin.volumeLoad += commodity.size
        bin.weightCapacity -= commodity.weight
        bin.weightLoad += commodity.weight
        return true
    end
    return false
end

function add!(bin::Bin, commodities::Vector{Commodity})
    if bin.capacity >= sum(commodity.size for commodity in commodities; init=0)
        append!(bin.content, commodities)
        bin.capacity -= sum(commodity.size for commodity in commodities; init=0)
        bin.load += sum(commodity.size for commodity in commodities; init=0)
        return true
    end
    return false
end

function remove!(bin::Bin, commodity::Commodity)
    fullCapaV = bin.volumeCapacity + bin.volumeLoad
    fullCapaW = bin.weightCapacity + bin.weightLoad
    contentLength = length(bin.content)
    filter!(com -> com != commodity, bin.content)
    bin.volumeLoad = sum(com -> com.size, bin.content; init=0)
    bin.volumeCapacity = fullCapaV - bin.volumeLoad
    bin.weightLoad = sum(com -> com.weight, bin.content; init=0)
    bin.weightCapacity = fullCapaW - bin.weightLoad
    return contentLength > length(bin.content)
end

function remove!(bin::Bin, commodities::Vector{Commodity})
    hasRemoved = false
    for commodity in commodities
        removed = remove!(bin, commodity)
        hasRemoved = hasRemoved || removed
    end
    return hasRemoved
end

# Gather all commodities in the bins into the vector ALL_COMMODITIES
# Returning a view for convenience to iterate over 
function get_all_commodities(bins::Vector{Bin}, ALL_COMMODITIES::Vector{Commodity})
    filter!(bin -> length(bin.content) > 0, bins)
    # verify the global vector is long enough 
    nCom = sum(length(bin.content) for bin in bins; init=0)
    if nCom > length(ALL_COMMODITIES)
        append!(ALL_COMMODITIES, fill(bins[1].content[1], nCom - length(ALL_COMMODITIES)))
    end
    # put all commodities in the global vector
    idx = 1
    for bin in bins
        nBinCom = length(bin.content)
        ALL_COMMODITIES[idx:(idx + nBinCom - 1)] = bin.content
        idx += nBinCom
    end
    return view(ALL_COMMODITIES, 1:nCom)
end

function stock_cost(bin::Bin)::Float64
    return sum(com.stockCost for com in bin.content; init=0.0)
end

function Base.zero(::Type{Vector{Bin}})
    return Bin[]
end

# No more runtime dispatch but still quite a lot of garbage collecting 
# Maybe impossible to get rid of it as the purpose is to actually copy data
function my_deepcopy(bins::Vector{Bin})
    newBins = [Bin(bin.capacity + bin.load) for bin in bins]
    for (idx, bin) in enumerate(bins)
        add!(newBins[idx], bin.content) || throw(ErrorException("Couldn't deepcopy"))
    end
    return newBins
end
