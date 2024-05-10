using SintPowerGraphs
using Test

network_filename = joinpath(@__DIR__, "../examples/simplified_cineldi/cineldi_simple.toml")
cost_filename = joinpath(@__DIR__, "../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)
network =  RadialPowerGraph(network_filename)

# Set up the case in the excel spreadhsheet
res, L, edge_pos = relrad_calc(cost_functions, network)
@test isapprox(sum(res["base"].U[:, 2]), 0.468, atol=0.01)
