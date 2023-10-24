using SintPowerGraphs
using Test

network_filename = joinpath(@__DIR__, "../examples/fasad_cineldi/excel_test.toml")
cost_filename = joinpath(@__DIR__, "../databases/cost_functions_dummy.json")

cost_functions = read_cost_functions(cost_filename)
network =  RadialPowerGraph(network_filename)

res, rest = relrad_calc(cost_functions, network)
IC = res.CENS
IC_sum = sum(IC;dims=2)
ICt_sum = sum(ICt;dims=2)
println(IC_sum)
println(ICt_sum)

IC_sum_target = [0.18; 0.94; 0.11; 0.86]
epsilon = sum(IC_sum_target)*0.1/100 # [kWh]. I take 0.1% of expected total interrupted energy as maximum error in calculation
@test (abs(sum(IC_sum - IC_sum_target))<epsilon)
