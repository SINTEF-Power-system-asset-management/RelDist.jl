module graphviz_mod
using ..network_graph: Network, KeyType, NewSwitch, LoadUnit
using ..network_graph: Bus, is_supply, is_load, is_nfc
using ..network_graph: labels, edge_labels
using ..section: NetworkPart
using GraphViz: GraphViz

function dot_edge_decor(switch::NewSwitch)
    if switch.is_closed
        "box"
    else
        "obox"
    end
end

function to_dot_edge(network::Network, parts::Vector{NetworkPart}, from::KeyType, to::KeyType, layout="dot")
    kwargs = Set{String}()
    for switch in network[from, to].switches
        if from == switch.bus
            push!(kwargs, "arrowtail=$(dot_edge_decor(switch))")
        elseif to == switch.bus
            push!(kwargs, "arrowhead=$(dot_edge_decor(switch))")
        end
    end

    if parts !== nothing && layout == "neato"
        for part in parts
            fromin = from in part.subtree
            toin = to in part.subtree
            if (fromin && !toin) || (toin && !fromin)
                # Make sure
                push!(kwargs, "len=2.0")
            end
        end
    end

    "$(from) -> $(to) [ $(join(kwargs, ',')) ]\n"
end

function to_dot_node(network::Network, parts::Vector{NetworkPart}, node::KeyType)
    kwargs = Vector{String}()
    bus::Bus = network[node]
    if is_supply(bus)
        push!(kwargs, "fillcolor=\"lightgreen\"")
    elseif is_nfc(bus)
        push!(kwargs, "fillcolor=\"lightskyblue\"")
    elseif is_load(bus)
        push!(kwargs, "fillcolor=\"deepskyblue3\"")
        labels = Vector{String}()
        for load::LoadUnit in bus.loads
            push!(labels, load.id)
        end
        push!(kwargs, "shape=record")
        push!(kwargs, "style=\"rounded,filled\"")
        push!(kwargs, "label=\"$(node)|{$(join(labels, '|'))}\"")
    end
    "$(node) [ $(join(kwargs, ',')) ]\n"
end

function to_dot(network::Network, parts=Vector{NetworkPart}(), layout="dot")
    """Creates a graphviz DOT language string containing the graph."""
    @assert layout in ["dot", "neato", "fdp", "sfdp"]
    label_to_idx = Dict{Int,String}()
    node_idx = 1

    clusters_str = ""
    for (part_idx, part) in enumerate(parts)
        node_str = ""
        for node_label in part.subtree
            label_to_idx[node_idx] = node_label
            # node_str *= "$(node_idx) [ label = $(node_label) ]\n"
            node_str *= "$(node_label) [ ]\n"
            node_idx += 1
        end
        cluster = """
        subgraph cluster_$(part_idx) {
            $(node_str)
        }
        """
        clusters_str *= cluster
    end

    edges_str = ""
    for edge in edge_labels(network)
        from, to = edge
        edges_str *= to_dot_edge(network, parts, from, to, layout)
    end

    nodes_str = ""
    for node in labels(network)
        nodes_str *= to_dot_node(network, parts, node)
    end

    dotstring = """
    digraph {
    layout=$(layout)
    overlap=vpsc
    edge [ arrowhead=none, arrowtail=none, dir=both ]
    node [ style=filled ]
    $(edges_str)

    $(clusters_str)
    
    $(nodes_str)
    }"""

    dotstring
end

function dot_plot(network::Network, parts=Vector{NetworkPart}(), layout="dot")
    dotstr = to_dot(network, parts, layout)
    buffer = IOBuffer(dotstr)
    graph = GraphViz.load(buffer)
    graph
end

end # module graphviz