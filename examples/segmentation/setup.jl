# Warning: when using algorithms from Graphs they use indices and not labels
# This is inconsistent with the metagraphs
using RelDist: segment_network, empty_network, Bus, Network, NetworkPart, KeyType, t_load, t_nfc_load, t_supply
using MetaGraphsNext: labels, neighbor_labels
using Graphs: Graph, SimpleGraph
using GraphMakie: graphplot
using GLMakie: Makie.wong_colors

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

function get_vertex_color(network::Network, vertex::KeyType, parts::Set{NetworkPart})
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
    elseif kind == t_nfc_load
        for (part_idx, part) in enumerate(parts)
            if vertex in part.subtree && !(vertex in part.dropped_loads)
                return (wong_colors()[part_idx], 0.8)
            end
        end
        (:red, 0.8)
    else
        error("Unsupported vertex type ", kind)
    end
end

function plot_that_graph(network::Network, parts::Set{NetworkPart})
    vertex_colors = [get_vertex_color(network, vertex, parts) for vertex in labels(network)]
    graphplot(network, node_color=vertex_colors, ilabels=labels(network))
end