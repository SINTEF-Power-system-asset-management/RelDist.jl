using DataFrames
using Test

network_filename = joinpath(@__DIR__, "../examples/simplified_cineldi/cineldi_simple.toml")
cost_filename = joinpath(@__DIR__, "../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)
network = Network(network_filename)

t = compress_relrad(network)

res = transform_relrad_data(network, t)

cut = ("1", "2")
cut_idx = findfirst(x -> x == cut, res.U.cut_edge)
# Case 1 in the power point
@test isapprox(sum(res.U[cut_idx, 1:end-1]), 0.08256, atol = 1e-3)

cut = ("2", "3")
cut_idx = findfirst(x -> x == cut, res.U.cut_edge)
# Case 1 in the power point
@test isapprox(sum(res.U[cut_idx, 1:end-1]), 0.28532, atol = 1e-3)

cut = ("3", "4")
cut_idx = findfirst(x -> x == cut, res.U.cut_edge)
# Case 1 in the power point
@test isapprox(sum(res.U[cut_idx, 1:end-1]), 0.019, atol = 1e-3)

cut = ("3", "5")
cut_idx = findfirst(x -> x == cut, res.U.cut_edge)
# Case 1 in the power point
@test isapprox(sum(res.U[cut_idx, 1:end-1]), 0.48728, atol = 1e-3)
