module network_part

using ..network_graph: Network, KeyType, get_supply_power, get_load_power, is_supply
using ..network_graph: Bus, neighbor_labels, nv, NewBranch, shed_load!, LoadUnit

"""Representation of the subgraph of the network that is supplied by a given bus.
Note: This is an implementation detail to `segment_network` and should not be used outside it."""
mutable struct NetworkPart
    supply::KeyType
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
    NetworkPart(supply, get_supply_power(bus), subtree, leaf_nodes)
end

Base.hash(party::NetworkPart, h::UInt) = hash(party.subtree, h)
Base.:(==)(a::NetworkPart, b::NetworkPart) = hash(a) == hash(b)
Base.keys(party::NetworkPart) = Base.keys(party.subtree)
Base.:∈(key::KeyType, part::NetworkPart) = key ∈ part.subtree

function visit!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power -= get_load_power(bus)
    push!(part.subtree, visitation)
    push!(part.leaf_nodes, visitation)
end

function unvisit_classic!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power += get_load_power(bus, consider_supply = false)
    pop!(part.subtree, visitation)
end

function visit_classic!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power -= get_load_power(bus, consider_supply = false)
    push!(part.subtree, visitation)
end

"""
    Visits a bus without changing the rest power of the part.
"""
function visit_and_shed!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    shed_load!(network[visitation])
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
    Return total load in a part.
"""
function total_load(network::Network, part::NetworkPart)
    sum(get_load_power(network[bus]) for bus in part.subtree)
end

"""
    Return all loads that have been shed in a part.
"""
function get_loads_nfc_and_shed(network::Network, part::NetworkPart)
    loads = Vector{LoadUnit}()
    nfc = Vector{LoadUnit}()
    shed = Vector{LoadUnit}()
    for v in part.subtree
        for load in network[v].loads
            if load.is_nfc
                push!(nfc, load)
            elseif load.in_service
                push!(loads, load)
            else
                push!(shed, load)
            end
        end
    end
    return loads, nfc, shed
end

"""
    Returns the DER in a part.
"""
function get_part_der(network::Network, part::NetworkPart)
    reduce(
        vcat,
        [
            network[v].supplies[map(x -> x.is_battery, network[v].supplies)] for
            v in part.subtree
        ],
    )
end


# """
# Returns the energy_not_served in a part.
# """
# function energy_not_served(network::Network, part::NetworkPart)


"""
    Return the labels that are in both part_a and part_b.
"""
function Base.intersect(part_a::NetworkPart, part_b::NetworkPart)
    intersect(part_a.subtree, part_b.subtree)
end

"""
    Returns true if the supply of a part is an vector of buses
"""
function supply_in_island(part::NetworkPart, island::Vector{KeyType})
    part.supply ∈ island
end

"""
    In case we have split a network into islands, this method
    returns the index of the island that contains the supply bus
    of the part.
"""
function part_island_idx(part, islands::Vector{Vector{KeyType}})
    idx = 0
    for island in islands
        if supply_in_island(part, island)
            idx += 1
        end
    end
    return idx
end

# End of module NetworkPart
end
