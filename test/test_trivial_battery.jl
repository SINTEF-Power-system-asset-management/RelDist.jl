using SintPowerGraphs
using Test

network_filename = joinpath(@__DIR__, "../examples/trivial_battery/trivial_battery.toml")
network = RadialPowerGraph(network_filename)
cost_filename = joinpath(@__DIR__, "../databases/cost_functions.json")
cost_functions = read_cost_functions(cost_filename)

res, L, edge_pos = relrad_calc(cost_functions, network)

println(res)
print("L=")
display(L)
print("edge_pos=")
display(edge_pos)
print("t=")
display(res["base"].t)

@test all(res["base"].t[:, 1] .< 2.0) # We expect the time to fix to be 0.01667 for all loads 
