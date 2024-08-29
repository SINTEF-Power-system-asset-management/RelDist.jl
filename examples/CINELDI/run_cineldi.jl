using RelDist
using SintPowerCase
using DataFrames

network_filename = joinpath(@__DIR__, "CINELDI.toml")
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)

case = Case(network_filename)

network = Network(case)

t = compress_relrad(network)
res = transform_relrad_data(network, t, cost_functions)
