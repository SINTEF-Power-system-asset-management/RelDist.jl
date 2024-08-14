module network_part

using ..network_graph: Network, KeyType, get_supply_power, get_load_power, is_supply
using ..network_graph: Bus, neighbor_labels, nv

"""Representation of the subgraph of the network that is supplied by a given bus.
Note: This is an implementation detail to `segment_network` and should not be used outside it."""
mutable struct NetworkPart
    rest_power::Float64
    subtree::Set{KeyType}
    leaf_nodes::Set{KeyType}
end

function NetworkPart(network::Network, supply::KeyType)
    bus = network[supply]
    if !is_supply(bus)
        error("Parts should only be instantiated at power supplies")
    end
    subtree = Set([supply])
    leaf_nodes = Set([supply])
    NetworkPart(get_supply_power(bus), subtree, leaf_nodes)
end

Base.hash(party::NetworkPart, h::UInt) = hash(party.subtree, h)
Base.:(==)(a::NetworkPart, b::NetworkPart) = hash(a) == hash(b)
Base.keys(party::NetworkPart) = Base.keys(party.subtree)

function visit!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power -= get_load_power(bus)
    push!(part.subtree, visitation)
    push!(part.leaf_nodes, visitation)
end

function unvisit!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power += get_load_power(bus)
    pop!(part.subtree, visitation)
    pop!(part.leaf_nodes, visitation)
end

function visit!(
    network::Network,
    parts::Vector{NetworkPart},
    part::NetworkPart,
    visitation::KeyType,
)
    # Warning: by modifying something in a set we open up the possibility for a lot of errors.
    # for example this following line will throw even though part is in parts
    # because part has been modified.
    # if !(part in parts)
    #     error("Part to visit must be in list of parts")
    # end
    # pop!(parts, part)
    visit!(network, part, visitation)
    # push!(parts, part)
end

function unvisit!(
    network::Network,
    parts::Vector{NetworkPart},
    part::NetworkPart,
    visitisation::KeyType,
)
    # if !(part in parts)
    #     error("Part to unvisit must be in list of parts")
    # end
    # pop!(parts, part)
    unvisit!(network, part, visitisation)
    # push!(parts, part)
end

function is_leaf(network::Network, part::NetworkPart, node_idx::KeyType)::Bool
    any(nbr_idx -> !(nbr_idx in part.subtree), neighbor_labels(network, node_idx))
end

"""
    Check if a part supplies all loads in a network.
"""
function all_loads_supplied(network::Network, part::NetworkPart)
    nv(network) == length(part.subtree)
end


"""
    Return the labels that are in both part_a and part_b.
"""
function Base.intersect(part_a::NetworkPart, part_b::NetworkPart)
    intersect(part_a.subtree, part_b.subtree)
end


end
