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

# Add a battery on bus 25
case.gen.E .= Inf
temp_gen = DataFrame(case.gen[end, :])
temp_gen.bus .= "25"
temp_gen.ID .= "B1"
temp_gen.external .= false
temp_gen.E .= 2
temp_gen.Pmax .= 10

case.gen = vcat(case.gen, temp_gen)

network = Network(case)

t = compress_relrad(network)
res_b = transform_relrad_data(network, t, cost_functions)
