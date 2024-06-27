# Warning: when using algorithms from Graphs they use indices and not labels
# This is inconsistent with the metagraphs
using Graphs: Graph, SimpleGraph
using MetaGraphsNext: MetaGraph, labels, neighbor_labels, haskey
using GraphMakie: graphplot
using GLMakie: Makie.wong_colors;
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
const Network = MetaGraph{Int,SimpleGraph{Int},KeyType,VertexType,EdgeType}

# graf[label] = vertex
# graf[labe, label] = edge

function empty_network()
    MetaGraph(
        Graph();
        label_type=KeyType,
        vertex_data_type=Bus,
        edge_data_type=Nothing,
    )
end

"""Representation of the subgraph of the network that is supplied by a given bus."""
mutable struct Part
    # TODO: Det er kanskje raskere om vi har et separat sett med leaf-nodes, 
    # så vi slepp å iterere over heile subtreet kvar iterasjon
    # EDIT: Det er vanskelig å vite når ein node stoppar å være ein leaf node, 
    # ikkje vits å implementere med mindre det blir eit problem
    rest_power::Float64
    subtree::Set{KeyType}
    # dropped_loads::Set{Int}
end

function Part(network::Network, supply::KeyType)
    bus = network[supply]
    if bus.kind != t_supply
        error("Parts should only be instantiated at power supplies")
    end
    subtree = Set([supply])
    Part(bus.power, subtree)
end

function hash(party::Part)
    hash((party.rest_power, party.subtree))
end

function ==(a::Part, b::Part)
    (a.rest_power == b.rest_power) && (a.subtree == b.subtree)
end

function visit!(network::Network, part::Part, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power -= bus.power
    push!(part.subtree, visitation)
end

function unvisit!(network::Network, part::Part, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power += bus.power
    pop!(part.subtree, visitation)
end

function visit!(network::Network, parts::Set{Part}, part::Part, visitation::KeyType)
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

function unvisit!(network::Network, parts::Set{Part}, part::Part, visitisation::KeyType)
    # if !(part in parts)
    #     error("Part to unvisit must be in set of parts")
    # end
    # pop!(parts, part)
    unvisit!(network, part, visitisation)
    # push!(parts, part)
end


function get_vertex_color(network::Network, vertex::KeyType)
    kind = network[vertex].kind
    if kind == t_supply
        :green
    elseif kind == t_load
        :blue
    else
        error("Unsupported vertex type", kind)
    end
end

function get_vertex_color(network::Network, vertex::KeyType, parts::Set{Part})
    kind = network[vertex].kind
    if kind == t_supply
        :green
    elseif kind == t_load
        for (part_idx, part) in enumerate(parts)
            if vertex in part.subtree
                return wong_colors()[part_idx]
            end
        end
        :blue
    else
        error("Unsupported vertex type", kind)
    end
end

function plot_that_graph(network::Network, parts::Set{Part})
    vertex_colors = [get_vertex_color(network, vertex, parts) for vertex in labels(network)]
    graphplot(network, node_color=vertex_colors, ilabels=labels(network))
end

function energy_not_served(network::Network, parts::Set{Part})::Float64
    sum([part.rest_power for part in parts])
end

function nodes_to_visit(network::Network, parts::Set{Part})
    """Creates an iterator over all neighbours of all parts"""
    Channel(ctype=Tuple{Part,KeyType}) do c
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

"""
Recursively finds the optimal way to partition the network into parts. Returns power not supplied and the array of parts
"""
function search(
    network::Network,
    parts::Set{Part},
    cost_function::typeof(energy_not_served)=energy_not_served
)::Set{Part}
    # Use the hashes in the cache because its easier to debug
    cache::Dict{UInt,Set{Part}} = Dict()

    function recurse(parts::Set{Part})::Set{Part}
        hashy = hash(parts)
        if hashy in keys(cache)
            return cache[hashy]
        end
        choices = []

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

        res = if length(choices) == 0
            deepcopy(parts)
        else
            argmin(choice -> cost_function(network, choice), choices)
        end
        cache[hashy] = res
        res
    end # function recurse

    recurse(parts)
end

function main()
    network = empty_network()

    network["bf_6"] = Bus(t_supply, 2.0)
    network["bf_5"] = Bus(t_supply, 2.0)

    network["load_4"] = Bus(t_load, 1.0)
    network["load_3"] = Bus(t_load, 1.0)
    network["load_2"] = Bus(t_load, 1.0)
    network["load_1"] = Bus(t_load, 1.0)

    network["load_1", "load_2"] = nothing
    network["load_2", "load_3"] = nothing
    network["load_3", "load_4"] = nothing

    network["bf_5", "load_2"] = nothing
    network["bf_6", "load_3"] = nothing

    # Create a subtree for each supply, (call this a Part)
    # The subtree needs to know how much more power it can supply
    # For each leaf node in the subtree, 
    # For each neighbour: 
    # Recursively try the case where you add the neighbour to this part
    # If there are no neighbours, return current state
    # Evaluate by the total unused power. I suppose this needs to change to support more complex costs
    supplies = [vertex for vertex in labels(network) if network[vertex].kind == t_supply]
    parts = Set([Part(network, supply) for supply in supplies])
    # println(supplies)

    # plot_that_graph(network, parts)
    optimal_split = search(network, parts)
    display(optimal_split)
    display(plot_that_graph(network, optimal_split))
end

main()
