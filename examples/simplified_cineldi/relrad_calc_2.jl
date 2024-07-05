include("../segmentation/setup.jl")
using RelDist: relrad_calc_2
using RelDist: relrad_calc, RadialPowerGraph, PieceWiseCost
using DataStructures: DefaultDict


# case_name = joinpath(@__DIR__, "../branch_at_fault/branch_at_fault.toml")
case_name = joinpath(@__DIR__, "../simplified_cineldi/cineldi_simple.toml")
# case_name = joinpath(@__DIR__, "../reliability_course/excel_test.toml")
network = Network(case_name)

# old relrad
network_rad = RadialPowerGraph(case_name)

supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
parts = Set([NetworkPart(network, supply) for supply in supplies])
# optimal_split = segment_network(network, parts)
# display(optimal_split)
# display(plot_that_graph(network, optimal_split))
cost_functions = Dict{String,PieceWiseCost}([key => PieceWiseCost() for key in network_rad.mpc.load[!, :type]])
@time res, L, edge_pos = relrad_calc(cost_functions, network_rad)
@time t = relrad_calc_2(network)

display(t)
display(transpose(res["base"].t))

for i in 1:length(t[1, :])-1
    summy = sum(transpose(res["base"].t)[:, i])
    summy_2 = sum(t[:, i])
    println(summy ≈ summy_2)
end
graphplot(network.network)
# graphplot(network2.network)
