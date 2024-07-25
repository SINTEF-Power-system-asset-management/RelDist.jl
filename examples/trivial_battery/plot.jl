using GLMakie
using GraphMakie
using SintPowerGraphs
using RelDist
using Graphs
using MetaGraphs

network_filename = joinpath(@__DIR__, "../trivial_battery/trivial_battery.toml")
network = RadialPowerGraph(network_filename)

edge_properties = [edge => props(network.G, edge) for edge in edges(network.G)]
display(edge_properties)

cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")
cost_functions = read_cost_functions(cost_filename)

res, L, edge_pos = relrad_calc(cost_functions, network)

function get_node_color(node::Integer)
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

function get_edge_color(edge)
    if get_prop(network.G, edge, :switch) == 0
        :red
    else
        :black
    end
end

vertex_properties = [props(network.G, node) for node in vertices(network.G)]
display(vertex_properties)
names = [get_prop(network.G, node, :name) for node in vertices(network.G)]
nodecolors = [get_node_color(node) for node in vertices(network.G)]

edge_properties = [props(network.G, edge) for edge in edges(network.G)]
edgecolors = [get_edge_color(edge) for edge in edges(network.G)]

graphplot(network.G, L, node_color = nodecolors, edge_color = edgecolors, ilabels = names)
