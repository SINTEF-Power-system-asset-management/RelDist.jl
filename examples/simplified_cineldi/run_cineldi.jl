using RelDist
using SintPowerCase
using SintPowerGraphs
using DataFrames

network_filename = joinpath(@__DIR__, "cineldi_simple.toml")
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)

case = Case(network_filename)
network = RadialPowerGraph(case)

# Just to make it a bit simpler to compare
network.mpc.switch.t_remote .= 0.5

network.mpc.gen[2, :Pmax] = 100
network.mpc.gen[2, :Pmax] = 130
res, L, edge_pos = relrad_calc(cost_functions, network)
results = ResFrames(res, edge_pos, L)


