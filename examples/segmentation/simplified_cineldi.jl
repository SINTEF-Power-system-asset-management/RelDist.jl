include("setup.jl")

network = Network(joinpath(@__DIR__, "../simplified_cineldi/cineldi_simple.toml"))

supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
parts = Set([NetworkPart(network, supply) for supply in supplies])
optimal_split = segment_network(network, parts)
display(optimal_split)
display(plot_that_graph(network, optimal_split))

if "a" === "a"
    # Removing all edges without switches
    compressed_network = deepcopy(network)
    remove_switchless_branches!(compressed_network)
    compressed_split = segment_network(compressed_network)
    display(plot_that_graph(compressed_network, compressed_split))
end