include("setup.jl")

network = Network(joinpath(@__DIR__, "../simplified_cineldi/cineldi_simple.toml"))
delete!(network, "1") # Delete main feeder to make the example more interesting

supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
parts = [NetworkPart(network, supply) for supply in supplies]

# dot_plot(network, parts)

optimal_split = segment_network(network, parts)
display(dot_plot(network, optimal_split, "dot"))

if true == true
    # Removing all edges without switches
    compressed_network = remove_switchless_branches(network)

    compressed_split = segment_network(compressed_network)
    display(dot_plot(compressed_network, compressed_split))

    good_split = segment_network_fast(compressed_network)
    display(dot_plot(compressed_network, good_split))
end
