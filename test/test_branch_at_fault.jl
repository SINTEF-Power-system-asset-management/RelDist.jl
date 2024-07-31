using SintPowerGraphs
using Test

network_filename = joinpath(@__DIR__, "../examples/branch_at_fault/branch_at_fault.toml")
network = RadialPowerGraph(network_filename)
cost_filename = joinpath(@__DIR__, "../databases/cost_functions.json")
cost_functions = read_cost_functions(cost_filename)

res, L, edge_pos = relrad_calc(cost_functions, network)

println(res)
println("L=", L)
println("edge_pos=", edge_pos)
println("t=", res["base"].t)

# All loads can be supplied, so all times should be 0.01667
@test all(res["base"].t[:, 1] .< 2)
