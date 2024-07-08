# Warning: when using algorithms from Graphs they use indices and not labels
# This is inconsistent with the metagraphs
using RelDist: segment_network, segment_network_classic, empty_network, Bus, Network, NetworkPart, KeyType
using RelDist: t_load, t_nfc_load, t_supply, NewBranch, is_supply, is_nfc, is_switch
using RelDist: kile_loss, remove_switchless_branches!
using MetaGraphsNext: labels, neighbor_labels, edge_labels
using Graphs: Graph, SimpleGraph
using GraphMakie: graphplot
using GLMakie: Makie.wong_colors

function get_vertex_color(bus::Bus)
    if is_supply(bus)
        return :green
    end

    opacity = is_nfc(bus) ? 0.8 : 1.0

    (:blue, opacity)
end

function get_vertex_color(network::Network, vertex::KeyType)
    bus = network[vertex]
    get_vertex_color(bus)
end

function get_vertex_color(bus::Bus, vertex::KeyType, parts::Set{NetworkPart})
    if is_supply(bus)
        return get_vertex_color(bus)
    end

    opacity = is_nfc(bus) ? 0.8 : 1.0

    for (part_idx, part) in enumerate(parts)
        if vertex in part.subtree
            return (wong_colors()[part_idx+1], opacity)
        end
    end
    (:blue, opacity)
end

function get_vertex_color(network::Network, vertex::KeyType, parts::Set{NetworkPart})
    bus = network[vertex]
    get_vertex_color(bus, vertex, parts)
end

function get_edge_color(network::Network, edge::Tuple{KeyType,KeyType})
    branch::NewBranch = network[edge...]
    if is_switch(branch)
        :black
    else
        :red
    end
end

function plot_that_graph(network::Network, parts::Set{NetworkPart})
    vertex_colors = [get_vertex_color(network, vertex, parts) for vertex in labels(network)]
    edge_colors = [get_edge_color(network, edge) for edge in edge_labels(network)]
    graphplot(network.network, node_color=vertex_colors, ilabels=labels(network), edge_color=edge_colors)
end