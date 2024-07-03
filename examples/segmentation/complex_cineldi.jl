include("setup.jl")

network = Network(joinpath(@__DIR__, "../CINELDI/CINELDI.toml"))

supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
parts = Set([NetworkPart(network, supply) for supply in supplies])
display(plot_that_graph(network, parts))
println("HERE")
optimal_split = segment_network(network, parts)
println("THERE")
println(optimal_split)
plot_that_graph(network, optimal_split)
