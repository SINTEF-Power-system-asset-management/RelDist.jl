# Warning: when using algorithms from Graphs they use indices and not labels
# This is inconsistent with the metagraphs
using Graphs: Graph, SimpleGraph
using MetaGraphsNext: MetaGraph, labels, neighbor_labels, haskey
using GraphMakie: graphplot
using GLMakie: Makie.wong_colors;

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

function get_vertex_color(network::Network, vertex::Int, parts::Vector{Part})
    kind = network[vertex].kind
    if kind == t_supply
        :green
    elseif kind == t_load
        for (part_idx, part) in enumerate(parts)
            if haskey(part.subtree, vertex)
                return wong_colors()[part_idx]
            end
        end
        :blue
    else
        error("Unsupported vertex type", kind)
    end
end

mutable struct Part
    rest_power::Float64
    subtree::Network
end

function Part(network::Network, supply::Int)
    bus = network[supply]
    if bus.kind != t_supply
        error("Parts should only be instantiated at power supplies")
    end
    subtree = empty_network()
    subtree[supply] = bus
    Part(bus.power, subtree)
end

"""
Recursively finds the optimal way to partition the network into parts. Returns power not supplied and the array of parts
"""
function search(network::Network, parts::Vector{Part}, consumed::Set{Int})::Vector{Part}
    # TODO: figure out hashing so that we can cache visited states
    cache = Set{UInt}()
    paths_checked = 0

    function recurse(parts::Vector{Part}, consumed::Set{Int})::Vector{Part}
        choices = []

        # For each of the growing subtrees
        for part_idx in 1:length(parts)
            part = parts[part_idx]
            # For each of the node in the subtree
            for node_idx in labels(part.subtree)
                # For each of the neighbours of that node
                for neighbour_idx in neighbor_labels(network, node_idx)
                    if neighbour_idx in consumed
                        continue
                    end
                    neighbour = network[neighbour_idx]
                    if neighbour.kind == t_supply
                        error("All supplies should be in consumed set")
                    end
                    if neighbour.power > part.rest_power
                        continue # Overload
                    end

                    local modified_parts = deepcopy(parts)
                    # println(hash(tuple(modified_parts)) in Set(hash(tuple(parts))))
                    modified_parts[part_idx].rest_power -= neighbour.power
                    modified_parts[part_idx].subtree[neighbour_idx] = deepcopy(neighbour)
                    modified_parts[part_idx].subtree[node_idx, neighbour_idx] = nothing
                    local modified_consumed = deepcopy(consumed)
                    push!(modified_consumed, neighbour_idx)
                    hashy = hash(modified_parts)
                    if hashy in cache
                        continue
                    end
                    res = recurse(modified_parts, modified_consumed)
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
    res = recurse(parts, consumed)
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

    network_2 = deepcopy(network)
    println(hash(tuple(network_2)) in Set(hash(tuple(network))))


    # vertex_colors = [get_vertex_color(network, vertex) for vertex in labels(network)]
    # vertex_labels = [network[vertex].label for vertex in labels(network)]
    # graphplot(network, node_color=vertex_colors, ilabels=vertex_labels)

    # Create a subtree for each supply, (call this a Part)
    # The subtree needs to know how much more power it can supply
    # For each leaf node in the subtree, 
    # For each neighbour: 
    # Recursively try the case where you add the neighbour to this part
    # If there are no neighbours, return current state
    # Evaluate by the total unused power. I suppose this needs to change to support more complex costs
    supplies = [vertex for vertex in labels(network) if network[vertex].kind == t_supply]
    parts = [Part(network, supply) for supply in supplies]
    visited_nodes = Set(supplies)
    # println(supplies)

    optimal_split = search(network, parts, visited_nodes)

    vertex_colors = [get_vertex_color(network, vertex, optimal_split) for vertex in labels(network)]
    vertex_labels = [network[vertex].label for vertex in labels(network)]
    graphplot(network, node_color=vertex_colors, ilabels=vertex_labels)
end

main()