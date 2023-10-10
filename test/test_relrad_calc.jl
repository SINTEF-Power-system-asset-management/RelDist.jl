using SintPowerGraphs
using JLD2

network_filename = joinpath(@__DIR__, "../examples/excel_ex/excel_test.toml")
cost_filename = joinpath(@__DIR__, "../databases/cost_functions_dummy.json")

cost_functions = read_cost_functions(cost_filename)
network =  RadialPowerGraph(network_filename)

res, resₜ, L, edge_pos = relrad_calc(cost_functions, network)
IC = res.CENS
ICt = resₜ.CENS
IC_sum = sum(IC;dims=2)
ICt_sum = sum(ICt;dims=2)
println(IC_sum)
println(ICt_sum)

@save "IC.jld2" IC
@save "L.jld2" L
@save "edge_pos.jld2" edge_pos

IC_sum_target = [10.5; 12.2; 11.4; 8.4]
epsilon = 0.0001
@test (sum(IC_sum - IC_sum_target)<epsilon)
