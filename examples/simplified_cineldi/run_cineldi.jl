using RelDist: transform_relrad_data, compress_relrad, read_cost_functions, Network

case_name = joinpath(@__DIR__, "cineldi_simple.toml")
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)

network = Network(case_name)

t = compress_relrad(network)
res = transform_relrad_data(network, t, cost_functions)
