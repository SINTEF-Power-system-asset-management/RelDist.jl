using CairoMakie
using GraphMakie
using SintPowerGraphs
using RelDist
using Graphs
using MetaGraphs

network_filename = joinpath(@__DIR__, "../simple_overlap/simple_overlap.toml")
network = RadialPowerGraph(network_filename)
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")
cost_functions = read_cost_functions(cost_filename)

res, L, edge_pos = relrad_calc(cost_functions, network)

function get_color(node)
    if get_prop(network.G, node, :gen)
        if get_prop(network.G, node, :external)
            :lightblue
        else
            :green
        end
    elseif get_prop(network.G, node, :load)
        :red
    else
        :white
    end
end
vertex_properties = [props(network.G, node) for node in vertices(network.G)]
display(vertex_properties)
names = [get_prop(network.G, node, :name) for node in vertices(network.G)]
nodecolors = [get_color(node) for node in vertices(network.G)]


edge_properties = [props(network.G, edge) for edge in edges(network.G)]
elabels = [repr(idx) * ": " * repr(src(edge)) * "=>" * repr(dst(edge)) for (edge, idx) in zip(edges(network.G), 1:ne(network.G))]
graphplot(
    network.G,
    L,
    node_color=nodecolors,
    # edge_color=edgecolors,
    ilabels=names,
    elabels=repr.(1:ne(network.G))
    # elabels=elabels
)