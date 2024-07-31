include("setup.jl")
using RelDist: delete!, get_start_guess, KeyType

network = Network(joinpath(@__DIR__, "../simplified_cineldi/cineldi_simple.toml"))
supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
parts = [NetworkPart(network, supply) for supply in supplies]

# dot_plot(network, parts)

optimal_split = segment_network(network, parts)
display(dot_plot(network, optimal_split, "dot"))

if true == true
    # Removing all edges without switches
    compressed_network = deepcopy(network)
    remove_switchless_branches!(compressed_network)
    compressed_split = segment_network(compressed_network)
    display(dot_plot(compressed_network, compressed_split))
end
