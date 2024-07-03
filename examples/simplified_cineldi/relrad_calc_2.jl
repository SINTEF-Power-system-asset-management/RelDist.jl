include("../segmentation/setup.jl")
using RelDist: relrad_calc_2


case = joinpath(@__DIR__, "../branch_at_fault/branch_at_fault.toml")
network = Network(case)

supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
parts = Set([NetworkPart(network, supply) for supply in supplies])
# optimal_split = segment_network(network, parts)
# display(optimal_split)
# display(plot_that_graph(network, optimal_split))
network2 = relrad_calc_2(network)

graphplot(network.network)
graphplot(network2.network)
