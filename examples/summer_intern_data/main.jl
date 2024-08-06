using RelDist: Network, NetworkPart, dot_plot, energy_not_served, is_supply, labels

network = Network(joinpath(@__DIR__, "intern.toml"))
parts = [NetworkPart(network, vertex) for vertex in labels(network) if is_supply(network[vertex])]
println(energy_not_served(parts))
dot_plot(network, Vector{NetworkPart}())
