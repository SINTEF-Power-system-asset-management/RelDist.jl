using Graphs: SimpleGraph, Graph
using MetaGraphsNext: MetaGraphsNext
import MetaGraphsNext: labels, neighbor_labels, haskey, setindex!, getindex

import Base

### Bus

@enum BusKind t_supply t_load t_nfc_load

abstract type Bus end
struct BusSupply <: Bus
    power::Float64
end

struct BusLoad <: Bus
    power::Float64
    type::String # e.g. residental/industry
    correction_factor::Real
    is_nfc::Bool
end

"""Constructor to be compatible with previous version"""
function Bus(type::BusKind, power::Float64)
    # This function might be nice to keep as a simple way to create a Bus
    # if you want to make a more generic bus that can be both a load and a supply
    if type == t_supply
        BusSupply(power)
    elseif type == t_load
        BusLoad(power, "residental", 1.0, false)
    elseif type == t_nfc_load
        BusLoad(power, "residental", 1.0, true)
    end
end

function get_power(supply::BusSupply)
    supply.power
end

function get_power(load::BusLoad)
    load.power
end

is_supply(supply::BusSupply) = true
is_supply(bus::Bus) = false
is_nfc(load::BusLoad) = load.is_nfc
is_nfc(bus::Bus) = false


### /Bus
### Branch

struct NewBranch
    repair_time::Float64 # h
end

NewBranch() = NewBranch(0.5)

const KeyType = String
const VertexType = Bus
const EdgeType = NewBranch
struct Network
    network::MetaGraphsNext.MetaGraph{Int,SimpleGraph{Int},KeyType,VertexType,EdgeType}
    switching_time::Float64
end

# graf[label] = vertex
# graf[labe, label] = edge

function Network(switching_time::Float64=0.5)
    network = MetaGraphsNext.MetaGraph(
        Graph();
        label_type=KeyType,
        vertex_data_type=VertexType,
        edge_data_type=EdgeType,
    )
    Network(network, switching_time)
end

# Forwarding methods to the inner network
empty_network() = Network()
labels(network::Network) = labels(network.network)
neighbor_labels(network::Network, key::KeyType) = neighbor_labels(network.network, key)
haskey(network::Network, key::KeyType) = haskey(network.network, key)
setindex!(network::Network, value::VertexType, key::KeyType) = setindex!(network.network, value, key)
getindex(network::Network, key::KeyType) = getindex(network.network, key)
setindex!(network::Network, value::EdgeType, key_a::KeyType, key_b::KeyType) = setindex!(network.network, value, key_a, key_b)
getindex(network::Network, key_a::KeyType, key_b::KeyType) = getindex(network.network, key_a, key_b)

"""Representation of the subgraph of the network that is supplied by a given bus."""
mutable struct NetworkPart
    # TODO: Det er kanskje raskere om vi har et separat sett med leaf-nodes, 
    # så vi slepp å iterere over heile subtreet kvar iterasjon
    rest_power::Float64
    subtree::Set{KeyType}
    dropped_loads::Set{KeyType}
end

function NetworkPart(network::Network, supply::KeyType)
    bus = network[supply]
    if !is_supply(bus)
        error("Parts should only be instantiated at power supplies")
    end
    subtree = Set([supply])
    dropped_loads = Set()
    NetworkPart(get_power(bus), subtree, dropped_loads)
end

Base.hash(party::NetworkPart) = hash((party.rest_power, party.subtree, party.dropped_loads))
Base.:(==)(a::NetworkPart, b::NetworkPart) = hash(a) == hash(b)
Base.keys(party::NetworkPart) = Base.keys(party.subtree)

function visit!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power -= get_power(bus)
    push!(part.subtree, visitation)
end

function unvisit!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power += get_power(bus)
    pop!(part.subtree, visitation)
end

function visit!(network::Network, parts::Set{NetworkPart}, part::NetworkPart, visitation::KeyType)
    # Warning: by modifying something in a set we open up the possibility for a lot of errors.
    # for example this following line will throw even though part is in parts
    # because part has been modified.
    # if !(part in parts)
    #     error("Part to visit must be in set of parts")
    # end
    # pop!(parts, part)
    visit!(network, part, visitation)
    # push!(parts, part)
end

function unvisit!(network::Network, parts::Set{NetworkPart}, part::NetworkPart, visitisation::KeyType)
    # if !(part in parts)
    #     error("Part to unvisit must be in set of parts")
    # end
    # pop!(parts, part)
    unvisit!(network, part, visitisation)
    # push!(parts, part)
end

"""Creates an iterator over all neighbours of all parts"""
function nodes_to_visit(network::Network, parts::Set{NetworkPart})
    Channel(ctype=Tuple{NetworkPart,KeyType}) do c
        for part in parts
            # For each of the node in the subtree
            for node_idx in part.subtree
                # For each of the neighbours of that node
                for neighbour_idx in neighbor_labels(network, node_idx)
                    if any([neighbour_idx in part.subtree for part in parts])
                        # Either walking back in subtree or colliding with another subtree
                        # Anyways we don't want it
                        continue
                    end
                    push!(c, (part, neighbour_idx))
                end
            end
        end
    end
end

function drop!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power += get_power(bus)
    push!(part.dropped_loads, visitation)
end

function undrop!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power -= get_power(bus)
    pop!(part.dropped_loads, visitation)
end

# see comments on visit and unvisit
drop!(network::Network, parts::Set{NetworkPart}, part::NetworkPart, visitation::KeyType) = drop!(network, part, visitation)
undrop!(network::Network, parts::Set{NetworkPart}, part::NetworkPart, visitation::KeyType) = undrop!(network, part, visitation)

"""Creates an iterator over all neighbours of all parts"""
function nodes_to_drop(network::Network, parts::Set{NetworkPart})
    Channel(ctype=Tuple{NetworkPart,KeyType}) do c
        for part::NetworkPart in parts
            # For each of the node in the subtree
            for node_idx::KeyType in part.subtree
                node::Bus = network[node_idx]
                if is_nfc(node) && !(node_idx in part.dropped_loads)
                    push!(c, (part, node_idx))
                end
            end
        end
    end
end

function is_served(parts::Set{NetworkPart}, vertex::KeyType)
    for part::NetworkPart in parts
        if vertex in part.subtree && !(vertex in part.dropped_loads)
            return true
        end
    end
    return false
end

"""
Create a function that takes a set of parts given the captured network and repair time.
# Arguments
    - `network::Network`: The network after the fault has been isolated.
    - `repair_time::Float64`: The time to repair the fault.

# Examples
```jldoctest
network = create_mock_network()
loss_fn = kile_loss(network)
optimal_split = segment_network(network, loss_fn)
loss_fn(optimal_split)

# output

4.5
```
"""
function kile_loss(network::Network, repair_time::Float64=4.0, correction_factor=1.0, cost_functions=Dict("residental" => PieceWiseCost()))
    switching_time = 0.5 # h

    function kile_internal(parts::Set{NetworkPart})::Float64
        cost = 0.0
        for vertex in labels(network)
            bus = network[vertex]
            if is_supply(bus)
                continue # supplies don't have a cost
            end
            power = get_power(bus)
            time_spent = is_served(parts, vertex) ? switching_time : repair_time
            cost_function = cost_functions["residental"]
            IC = calculate_kile(power, time_spent, cost_function, correction_factor)
            cost += IC
        end
        cost
    end
    kile_internal
end

function energy_not_served(parts::Set{NetworkPart})::Float64
    sum([part.rest_power for part in parts])
end

"""
Recursively finds the optimal way to partition the network into parts. Returns the different parts of the network.
Assume the fault has been found and isolated.
"""
function segment_network(
    network::Network,
    parts::Set{NetworkPart},
    cost_function::Function=energy_not_served
)::Set{NetworkPart}
    # Use the hashes in the cache because its easier to debug
    cache::Dict{UInt,Set{NetworkPart}} = Dict()

    function recurse(parts::Set{NetworkPart})::Set{NetworkPart}
        hashy = hash(parts)
        if hashy in keys(cache)
            return cache[hashy]
        end

        # We do know that if we don't drop any loads, the deeper search
        # is always better, but this is hard to implement in a readable manner
        # so we just check it
        choices = [deepcopy(parts)]

        for (part, neighbour_idx) in nodes_to_visit(network, parts)
            neighbour = network[neighbour_idx]
            if neighbour.power > part.rest_power
                continue # Overload
            end

            visit!(network, parts, part, neighbour_idx)
            res = recurse(parts)
            push!(choices, res)
            unvisit!(network, parts, part, neighbour_idx)
        end

        for (part, node_idx) in nodes_to_drop(network, parts)
            drop!(network, parts, part, node_idx)
            res = recurse(parts)
            push!(choices, res)
            undrop!(network, parts, part, node_idx)
        end

        res = if length(choices) == 1
            choices[1]
        else
            argmin(cost_function, choices)
        end
        cache[hashy] = res
        res
    end # function recurse

    recurse(parts)
end

function segment_network(network::Network, cost_function::Function=energy_not_served)
    supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
    parts = Set([NetworkPart(network, supply) for supply in supplies])
    segment_network(network, parts, cost_function)
end

function create_mock_network()
    network = empty_network()
    network["bf"] = Bus(t_supply, 1.0)
    network["load_1"] = Bus(t_load, 1.0)
    network["load_2"] = Bus(t_load, 1.0)
    network["bf", "load_1"] = NewBranch()
    network["load_1", "load_2"] = NewBranch()
    network
end
