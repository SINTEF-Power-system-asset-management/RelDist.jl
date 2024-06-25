using SintPowerGraphs
using Test

network_filename = joinpath(@__DIR__, "../examples/trivial_battery/trivial_battery.toml")
network = RadialPowerGraph(network_filename)
cost_filename = joinpath(@__DIR__, "../databases/cost_functions.json")
cost_functions = read_cost_functions(cost_filename)

res, L, edge_pos = relrad_calc(cost_functions, network)

println(res)
println("L=", L)
println("edge_pos=", edge_pos)
println("t=", res["base"].t)