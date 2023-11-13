using SintPowerGraphs
using JLD2

network_filename = joinpath(@__DIR__, "../examples/excel_ex_cineldi_format/excel_test.toml")
cost_filename = joinpath(@__DIR__, "../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)
network =  RadialPowerGraph(network_filename)

res, _, _ = relrad_calc(cost_functions, network)
IC = res["base"].CENS
ICt = res["temp"].CENS
IC_sum = sum(IC;dims=2)
ICt_sum = sum(ICt;dims=2)
println(IC_sum)
println(ICt_sum)


IC_sum_target = [53.15; 68.695; 75.9; 83.12]
@testset "Verifying unavailability" begin
U_target = 13.15
@test isapprox(sum(res["base"].U), U_target)
end

epsilon = 0.0001
@test (sum(IC_sum - IC_sum_target)<epsilon)
