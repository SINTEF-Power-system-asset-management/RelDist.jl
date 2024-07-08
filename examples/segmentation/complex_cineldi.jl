include("setup.jl")
using RelDist: delete!, edge_labels, get_start_guess

network = Network(joinpath(@__DIR__, "../CINELDI/CINELDI.toml"))

for vertex in ["1", "36", "62"] # remove all sources but 88
    for edge in edge_labels(network)
        if edge[1] == vertex || edge[2] == vertex
            delete!(network, edge...)
        end
    end
    delete!(network, vertex)
end

supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
parts = Set([NetworkPart(network, supply) for supply in supplies])

display(plot_that_graph(network, parts))

estimated_split = segment_network_classic(network, parts)
println(estimated_split)
display(plot_that_graph(network, estimated_split))

# This might work for some other net so i guess keep it, but it's too slow for this one
without_overlap = get_start_guess(network, estimated_split)
display(plot_that_graph(network, without_overlap))

optimal_split = segment_network(network, without_overlap)
display(plot_that_graph(network, optimal_split))
