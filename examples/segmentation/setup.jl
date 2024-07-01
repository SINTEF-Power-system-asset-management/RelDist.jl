# Warning: when using algorithms from Graphs they use indices and not labels
# This is inconsistent with the metagraphs
using RelDist: segment_network, empty_network, Bus, Network, NetworkPart, KeyType
using RelDist: t_load, t_nfc_load, t_supply, BusSupply, BusLoad, NewBranch, is_supply
using RelDist: kile_loss
using MetaGraphsNext: labels, neighbor_labels
using Graphs: Graph, SimpleGraph
using GraphMakie: graphplot
using GLMakie: Makie.wong_colors

get_vertex_color(bus::BusSupply) = :green
function get_vertex_color(bus::BusLoad)
    if bus.is_nfc
        return (get_vertex_color(BusLoad(is_nfc=false, bus...)), 0.8)
    end

    :blue
end

function get_vertex_color(bus::Bus)
    error("Unsupported bus type")
end


function get_vertex_color(network::Network, vertex::KeyType)
    bus = network[vertex]
    get_vertex_color(bus)
end

# I'm sorry
get_vertex_color(bus::BusSupply, vertex::KeyType, parts::Set{NetworkPart}) = get_vertex_color(bus)
function get_vertex_color(bus::BusLoad, vertex::KeyType, parts::Set{NetworkPart})
    if bus.is_nfc
        return (get_vertex_color(BusLoad(is_nfc=false, bus...)), 0.8)
    end

    for (part_idx, part) in enumerate(parts)
        if vertex in part.subtree
            return wong_colors()[part_idx]
        end
    end
    get_vertex_color(bus)
end

function get_vertex_color(bus::Bus, parts::Set{NetworkPart})
    error("Unsupported bus type")
end

function get_vertex_color(network::Network, vertex::KeyType, parts::Set{NetworkPart})
    bus = network[vertex]
    get_vertex_color(bus, vertex, parts)
end

function plot_that_graph(network::Network, parts::Set{NetworkPart})
    vertex_colors = [get_vertex_color(network, vertex, parts) for vertex in labels(network)]
    graphplot(network.network, node_color=vertex_colors, ilabels=labels(network))
end