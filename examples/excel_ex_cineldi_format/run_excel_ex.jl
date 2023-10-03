using RelDist
using SintPowerGraphs
using SintPowerCase
using DataFrames
using MetaGraphs
using Graphs

using Plots
using GraphRecipes

network_filename = joinpath(@__DIR__, "excel_test.toml")
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions_dummy.json")

cost_functions = read_cost_functions(cost_filename)

case = Case(network_filename)

network = RadialPowerGraph(case)

graphplot(network.G, curves=false, names=[props(network.G, v)[:name] for v in 1:nv(network.G)]
)

graphplot(network.radial, curves=false, names=[props(network.radial, v)[:name] for v in 1:nv(network.radial)]
)

res, rest, L, edge_pos = relrad_calc(cost_functions, network)

rest.ENS

res.ENS'

