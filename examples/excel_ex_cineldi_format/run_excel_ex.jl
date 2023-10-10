using RelDist
using SintPowerGraphs
using SintPowerCase
using DataFrames

network_filename = joinpath(@__DIR__, "excel_test.toml")
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)

case = Case(network_filename)

network = RadialPowerGraph(case)

res, rest, L, edge_pos = relrad_calc(cost_functions, network)

rest.ENS

res.ENS'

