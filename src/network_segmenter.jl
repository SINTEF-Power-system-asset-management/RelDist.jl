using MetaGraphsNext: MetaGraphsNext, labels, neighbor_labels, haskey

import Base: hash, ==

@enum BusKind t_supply t_load t_nfc_load

"""Minimal data structure for storing a bus in a network.
If bus is a supply power is the power it can supply.
If it is a load or a nfc_load it is the power it needs."""
struct Bus
    kind::BusKind
    power::Float64
end

const KeyType = String
const VertexType = Bus
const EdgeType = Nothing
const Network = MetaGraphsNext.MetaGraph{Int,SimpleGraph{Int},KeyType,VertexType,EdgeType}

# graf[label] = vertex
# graf[labe, label] = edge

function empty_network()
    MetaGraphsNext.MetaGraph(
        Graph();
        label_type=KeyType,
        vertex_data_type=Bus,
        edge_data_type=Nothing,
    )
end

"""Representation of the subgraph of the network that is supplied by a given bus."""
mutable struct NetworkPart
    # TODO: Det er kanskje raskere om vi har et separat sett med leaf-nodes, 
    # så vi slepp å iterere over heile subtreet kvar iterasjon
    # EDIT: Det er vanskelig å vite når ein node stoppar å være ein leaf node, 
    # ikkje vits å implementere med mindre det blir eit problem
    rest_power::Float64
    subtree::Set{KeyType}
    dropped_loads::Set{KeyType}
end

function NetworkPart(network::Network, supply::KeyType)
    bus = network[supply]
    if bus.kind != t_supply
        error("Parts should only be instantiated at power supplies")
    end
    subtree = Set([supply])
    dropped_loads = Set()
    NetworkPart(bus.power, subtree, dropped_loads)
end

function hash(party::NetworkPart)
    hash((party.rest_power, party.subtree, party.dropped_loads))
end

function ==(a::NetworkPart, b::NetworkPart)
    hash(a) == hash(b)
end

function visit!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power -= bus.power
    push!(part.subtree, visitation)
end

function unvisit!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power += bus.power
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
    part.rest_power += bus.power
    push!(part.dropped_loads, visitation)
end

function undrop!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power -= bus.power
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
                if node.kind == t_nfc_load && !(node_idx in part.dropped_loads)
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

function kile_loss(network::Network)
    switching_time = 0.5 # h
    repair_time = 4.0 # h
    correction_factor = 1.0
    cost_function = PieceWiseCost()

    function kile_internal(parts::Set{NetworkPart})
        cost = 0.0
        for vertex in labels(network)
            if vertex.kind == t_supply
                continue # supplies don't have a cost
            end
            power = vertex.power
            time_spent = is_served(parts, vertex) ? switching_time : repair_time
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
Recursively finds the optimal way to partition the network into parts. Returns power not supplied and the array of parts
"""
function segment_network(
    network::Network,
    parts::Set{NetworkPart},
    cost_function::typeof(energy_not_served)=energy_not_served
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

function segment_network(network::Network, cost_function::typeof(energy_not_served)=energy_not_served)
    supplies = [vertex for vertex in labels(network) if network[vertex].kind == t_supply]
    parts = Set([NetworkPart(network, supply) for supply in supplies])
    segment_network(network, parts, cost_function)
end
