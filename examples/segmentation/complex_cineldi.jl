include("setup.jl")
using RelDist: delete!, get_start_guess, KeyType

network = Network(joinpath(@__DIR__, "../CINELDI/CINELDI.toml"))

for vertex in ["1", "88"] # ["1", "62", "36", "88"] # remove all sources but 1
    delete!(network, vertex)
end

supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
parts = [NetworkPart(network, supply) for supply in supplies]

display(plot_that_graph(network, parts))

estimated_split = segment_network_classic(network, parts)
println(estimated_split)
display(plot_that_graph(network, estimated_split))

if "a" == "b"
    # Backtracking to no overlap and doing complete search from there
    # This might work for some other net so i guess keep it, but it's too slow for this one
    without_overlap = get_start_guess(network, estimated_split)
    display(plot_that_graph(network, without_overlap))

    optimal_split = segment_network(network, without_overlap)
    display(plot_that_graph(network, optimal_split))
end

if "a" == "a"
    # TODO: This is obviously bugged for nodes with multiple neighbours. fix
    # Also it dele
    # Removing all edges without switches
    compressed_network = deepcopy(network)
    remove_switchless_branches!(compressed_network)

    parts = [NetworkPart(network, supply) for supply in supplies]
    display(plot_that_graph(compressed_network, parts))

    estimated_split = segment_network_classic(compressed_network, parts)
    without_overlap = get_start_guess(compressed_network, estimated_split)
    # without_overlap = parts
    compressed_split = segment_network(compressed_network, without_overlap)
    display(plot_that_graph(compressed_network, compressed_split))
end

# let nothing
#     remove_switchless_branches!(compressed_network)
# display(plot_that_graph(compressed_network, parts))
# end

