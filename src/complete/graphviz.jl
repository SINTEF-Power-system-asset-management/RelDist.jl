module graphviz_mod
using ..network_graph: Network, KeyType, NewSwitch, LoadUnit, SupplyUnit
using ..network_graph: Bus, is_supply, is_battery, is_load, is_nfc
using ..network_graph: labels, edge_labels
using ..section: NetworkPart, sort
using GraphViz: GraphViz

text_color = "#000000"
# Colors kindly yoinked from set39 at https://graphviz.org/doc/info/colors.html
_bluegreen = "#8dd3c7"
node_color = "#fef8f2"
nfc_color = "#aaa1e3"
load_color = "#4e89b7"
_fault_colors = "#fb8072"  # used in external figures
battery_color = "#f3995f"
supply_color = "#6aa764"
_pink = "#fccde5"
_gray = "#d9d9d9"

function dot_edge_decor(switch::NewSwitch)
    if switch.is_closed
        "box"
    else
        "obox"
    end
end

function to_dot_edge(network::Network, parts::Vector{NetworkPart}, from::KeyType, to::KeyType, layout="dot")
    a, b = sort((from, to))
    kwargs = Set{String}(["id=\"$(a)-$(b)\""])
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

function to_dot_load(load::LoadUnit)
    color = if load.is_nfc
        nfc_color
    else
        load_color
    end

    """<tr><td style="rounded" border="1" width="50" bgcolor="$(color)">$(load.id)</td></tr>"""
end
function to_dot_supply(supply::SupplyUnit)
    color = if supply.is_battery
        battery_color
    else
        supply_color
    end
    """<tr><td style="rounded" border="1" width="50" bgcolor="$(color)">$(supply.id)</td></tr>"""
end

function to_dot_node(network::Network, parts::Vector{NetworkPart}, node::KeyType)
    bus::Bus = network[node]
    rows = Vector{String}()
    for supply::SupplyUnit in bus.supplies
        push!(rows, to_dot_supply(supply))
    end
    for load::LoadUnit in bus.loads
        push!(rows, to_dot_load(load))
    end
    """
    $(node) [ fillcolor="transparent" shape="plain" id="$(node)" label=<
    <table bgcolor="$(node_color)" style="rounded" border="1" cellspacing="4" >
        <tr><td width="30" border="0"><font color="$(text_color)">$(node)</font></td></tr>
        $(join(rows, "\n"))
    </table>> ]
    """
end

function to_dot(network::Network, parts=Vector{NetworkPart}(); layout="dot")
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
    $(layout != "sfdp" ? "" : "repulsiveforce=5.0")
    overlap=vpsc
    ratio=0.56
    edge [ arrowhead=none, arrowtail=none, dir=both color="$(text_color)" ]
    node [ style=filled color="$(text_color)" fontcolor="$(text_color)" ]
    bgcolor="transparent"
    $(edges_str)

    $(clusters_str)
    
    $(nodes_str)
    }"""

    dotstring
end

"""Plot the network. Use layout="neato" or "sfdp" to get more network-like structures"""
function dot_plot(network::Network, parts=Vector{NetworkPart}(); layout="dot")
    dotstr = to_dot(network, parts; layout=layout)
    buffer = IOBuffer(dotstr)
    graph = GraphViz.load(buffer)
    graph
end

end # module graphviz