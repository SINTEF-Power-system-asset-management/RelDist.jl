using SintPowerGraphs
using Test

interruption_filename = joinpath(@__DIR__, "../databases/interruption_FASIT2.json")
network_filename = joinpath(@__DIR__, "../examples/fasad_relrad_tsh/fasad_net.toml")
cost_filename = joinpath(@__DIR__, "../databases/cost_functions_dummy.json")

interruption = read_interruption(interruption_filename)
cost_functions = read_cost_functions(cost_filename)
network =  RadialPowerGraph(network_filename)

res, rest = relrad_calc(interruption, cost_functions, network)
IC = res.CENS
IC_sum = sum(IC;dims=2)
ICt_sum = sum(ICt;dims=2)
println(IC_sum)
println(ICt_sum)

# Results in kWh (fasad gives load input in kW)
IC_sum_target = [150; 917; 90; 843]
epsilon = sum(IC_sum_target)/1000 # [kWh]. I take 0.1% of expected total interrupted energy as maximum error in calculation
@test (abs(sum(IC_sum - IC_sum_target))<epsilon)
