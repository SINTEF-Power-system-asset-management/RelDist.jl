include("../segmentation/setup.jl")
using RelDist: relrad_calc_2, transform_relrad_data
using RelDist: relrad_calc, RadialPowerGraph, PieceWiseCost
using DataStructures: DefaultDict


# case_name = joinpath(@__DIR__, "../branch_at_fault/branch_at_fault.toml")
case_name = joinpath(@__DIR__, "../simplified_cineldi/cineldi_simple.toml")
# case_name = joinpath(@__DIR__, "../reliability_course/excel_test.toml")
network_2 = Network(case_name)

# old relrad
network = RadialPowerGraph(case_name)

supplies = [vertex for vertex in labels(network_2) if is_supply(network_2[vertex])]
parts = Set([NetworkPart(network_2, supply) for supply in supplies])
# optimal_split = segment_network(network_2, parts)
# display(optimal_split)
# display(plot_that_graph(network_2, optimal_split))
cost_functions = Dict{String,PieceWiseCost}([
    key => PieceWiseCost() for key in network.mpc.load[!, :type]
])
res, L, edge_pos = relrad_calc(cost_functions, network)
t = relrad_calc_2(network_2)

display(t)
display(transpose(res["base"].t))

for i = 1:length(t[1, :])-1
    summy = sum(transpose(res["base"].t)[:, i])
    summy_2 = sum(t[:, i])
    print(summy ≈ summy_2, " ")
end
# graphplot(network_2.network)

new_res = transform_relrad_data(network_2, t)

for i = 1:length(t[1, :])-1
    summy = sum(transpose(res["base"].ENS)[:, i])
    summy_2 = sum(new_res.ENS[:, i])
    print(summy ≈ summy_2, " ")
end
