# Warning: when using algorithms from Graphs they use indices and not labels
# This is inconsistent with the metagraphs
using Graphs: Graph, SimpleGraph
using MetaGraphsNext: MetaGraph, labels, neighbor_labels, haskey
using GraphMakie: graphplot
using GLMakie: Makie.wong_colors;
import Base: hash, ==

@enum BusKind t_supply t_load

struct Bus
    kind::BusKind
    power::Float64
    label::String
end

function Bus(kind::BusKind, power::Float64)
    Bus(kind, power, "")
end

const Network = MetaGraph{Int64,SimpleGraph{Int64},Int64,Bus,Nothing}

function empty_network()
    MetaGraph(
        Graph();
        label_type=Int,
        vertex_data_type=Bus,
        edge_data_type=Nothing,
    )
end

mutable struct Part
    # TODO: Det er kanskje raskere om vi har et separat sett med leaf-nodes, 
    # så vi slepp å iterere over heile subtreet kvar iterasjon
    # EDIT: Det er vanskelig å vite når ein node stoppar å være ein leaf node, 
    # ikkje vits å implementere med mindre det blir eit problem
    rest_power::Float64
    subtree::Set{Int}
end

function Part(network::Network, supply::Int)
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


function get_vertex_color(network::Network, vertex::Int)
    kind = network[vertex].kind
    if kind == t_supply
        :green
    elseif kind == t_load
        :blue
    else
        error("Unsupported vertex type", kind)
    end
end

function get_vertex_color(network::Network, vertex::Int, parts::Set{Part})
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
    vertex_labels = [network[vertex].label for vertex in labels(network)]
    graphplot(network, node_color=vertex_colors, ilabels=vertex_labels)
end

"""
Recursively finds the optimal way to partition the network into parts. Returns power not supplied and the array of parts
"""
function search(network::Network, parts::Set{Part})::Set{Part}
    cache = Set{UInt}()
    paths_checked = 0

    function recurse(parts::Set{Part})::Set{Part}
        choices = []

        # For each of the growing subtrees
        for (part_idx, part) in enumerate(parts)
            # For each of the node in the subtree
            for node_idx in part.subtree
                # For each of the neighbours of that node
                for neighbour_idx in neighbor_labels(network, node_idx)
                    if any([neighbour_idx in part.subtree for part in parts])
                        # Either walking back in subtree or colliding with another subtree
                        # Anyways we don't want it
                        continue
                    end
                    neighbour = network[neighbour_idx]
                    if neighbour.kind == t_supply
                        error("All supplies should be in set of already visited")
                    end
                    if neighbour.power > part.rest_power
                        continue # Overload
                    end

                    local modified_parts = deepcopy(parts)
                    local modified_part = pop!(modified_parts, part)
                    modified_part.rest_power -= neighbour.power
                    push!(modified_part.subtree, neighbour_idx)
                    push!(modified_parts, modified_part)

                    hashy = hash(modified_parts)
                    if hashy in cache
                        continue
                    end
                    res = recurse(modified_parts)
                    push!(cache, hashy)
                    paths_checked += 1
                    push!(choices, res)
                end
            end
        end

        if length(choices) == 0
            parts
        else
            argmin(choice -> sum([part.rest_power for part in choice]), choices)
        end
    end
    res = recurse(parts)
    println("Checked ", paths_checked)
    res
end

function main()
    network = empty_network()

    network[6] = Bus(t_supply, 2.0, "bf_6")
    network[5] = Bus(t_supply, 2.0, "bf_5")

    network[4] = Bus(t_load, 1.0, "load_4")
    network[3] = Bus(t_load, 1.0, "load_3")
    network[2] = Bus(t_load, 1.0, "load_2")
    network[1] = Bus(t_load, 1.0, "load_1")

    network[1, 2] = nothing
    network[2, 3] = nothing
    network[3, 4] = nothing

    network[5, 2] = nothing
    network[6, 3] = nothing

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
    plot_that_graph(network, optimal_split)
end

main()
