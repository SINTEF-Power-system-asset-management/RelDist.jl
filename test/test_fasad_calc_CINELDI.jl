using SintPowerGraphs
using Test

network_filename = joinpath(@__DIR__, "../examples/fasad_cineldi/excel_test.toml")
cost_filename = joinpath(@__DIR__, "../databases/cost_functions_dummy.json")

cost_functions = read_cost_functions(cost_filename)
network =  RadialPowerGraph(network_filename)


res, rest = relrad_calc(cost_functions, network, Traverse(consider_cap=false))
ENS = res.ENS
ENSt = rest.ENS
ENS_sum = sum(ENS+ENSt;dims=2)

ENS_sum_target = [0.18; 0.94; 0.11; 0.86]
epsilon = sum(ENS_sum_target)*1/100 # [kWh]. I take 1% of expected total interrupted energy as maximum error in calculation
@test (abs(sum(ENS_sum - ENS_sum_target))<epsilon)

# Check if it works when we consider capacity
res, rest = relrad_calc(cost_functions, network)
ENS = res.ENS
ENSt = rest.ENS
ENS_sum = sum(ENS+ENSt;dims=2)

ENS_sum_target = [0.18; 2.54; 0.11; 0.86]
epsilon = sum(ENS_sum_target)*1/100 # [kWh]. I take 1% of expected total interrupted energy as maximum error in calculation
@test (abs(sum(ENS_sum - ENS_sum_target))<epsilon)
