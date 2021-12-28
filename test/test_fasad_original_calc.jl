using PowerGraphs
using JLD2

interruption_filename = joinpath(@__DIR__, "../databases/interruption_FASIT2.json")
network_filename = joinpath(@__DIR__, "../examples/fasad_tsh/TSH-grid-no-indicators.toml")
cost_filename = joinpath(@__DIR__, "../databases/cost_functions_dummy.json")

mpc = process_fasad_case(network_filename)
interruption = read_interruption(interruption_filename)
cost_functions = read_cost_functions(cost_filename)
network =  RadialPowerGraph(mpc)

IC, ICt, L, edge_pos = relrad_calc(interruption, cost_functions, network)
IC_sum = sum(IC;dims=2)
ICt_sum = sum(ICt;dims=2)
println(IC_sum)
println(ICt_sum)

@save "IC.jld2" IC
@save "L.jld2" L
@save "edge_pos.jld2" edge_pos

# Results in kWh (fasad gives load input in kW)
IC_sum_target = [150; 917; 90; 843]
epsilon = sum(IC_sum_target)/1000 # [kWh]. I take 0.1% of expected total interrupted energy as maximum error in calculation
@test (abs(sum(IC_sum - IC_sum_target))<epsilon)
