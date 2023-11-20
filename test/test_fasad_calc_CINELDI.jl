using SintPowerGraphs
using Test

network_filename = joinpath(@__DIR__, "../examples/fasad_cineldi/excel_test.toml")
cost_filename = joinpath(@__DIR__, "../databases/cost_functions_dummy.json")

cost_functions = read_cost_functions(cost_filename)
network =  RadialPowerGraph(network_filename)

conf = RelDistConf(traverse=Traverse(consider_cap=false),
                   failures=Failures(switch_failures=true,
                                    communication_failure=true,
                                   reserve_failure=true))

res, _, _ = relrad_calc(cost_functions, network, conf)
ENS = res["base"].ENS
ENSt = res["temp"].ENS
ENS_sum = sum(ENS+ENSt;dims=2)

ENS_sum_target = [0.18; 0.94; 0.11; 0.86]
epsilon = sum(ENS_sum_target)*1/100 # [kWh]. I take 1% of expected total interrupted energy as maximum error in calculation
@test (abs(sum(ENS_sum - ENS_sum_target))<epsilon)

ENS = Dict("downstream" => [3, 0.05, 0.0375, 0.025],
           "upstream" => [0.0625, 0.05, 1.8, 1.2])
# Check upstream and downstream switch failure on line 3
for key in keys(ENS)
    @test abs(sum(res[key].ENS[:, 3])-sum(ENS[key]))<epsilon
end

# Check communication failure
@test abs(sum(res["comm_fail"].ENS) - sum([0.02083, 0, 0.0125, 0.0083]))<epsilon
# Check reserve failure
@test abs(sum(res["reserve_trans_grid-T2"].ENS) - sum([2.10833, 2.48333, 1.265, 1.6267]))<epsilon

# Check if it works when we consider capacity
res, _, _ = relrad_calc(cost_functions, network)
ENS = res["base"].ENS
ENSt = res["temp"].ENS
ENS_sum = sum(ENS+ENSt;dims=2)

ENS_sum_target = [0.18; 2.54; 0.11; 0.86]
epsilon = sum(ENS_sum_target)*1/100 # [kWh]. I take 1% of expected total interrupted energy as maximum error in calculation
@test (abs(sum(ENS_sum - ENS_sum_target))<epsilon)

