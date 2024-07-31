include("setup.jl")
using RelDist: delete!, get_start_guess, KeyType

network = Network(joinpath(@__DIR__, "../simplified_cineldi/cineldi_simple.toml"))
supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
parts = [NetworkPart(network, supply) for supply in supplies]

# dot_plot(network, parts)

optimal_split = segment_network(network, parts)
dot_plot(network, optimal_split, "dot")
