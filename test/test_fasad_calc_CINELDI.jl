using SintPowerGraphs
using Test

network_filename = joinpath(@__DIR__, "../examples/fasad/excel_test.toml")
cost_filename = joinpath(@__DIR__, "../databases/cost_functions_dummy.json")

cost_functions = read_cost_functions(cost_filename)
network =  RadialPowerGraph(network_filename)

conf = RelDistConf(traverse=Traverse(consider_cap=false),
                   failures=Failures(switch_failure_prob=1,
                                    communication_failure_prob=1,
                                    reserve_failure_prob=1))

res, L, edge_pos = relrad_calc(cost_functions, network, conf)
U = 0.738 # From excel
@test isapprox(sum(res["base"].U)+sum(res["temp"].U), U, atol=0.01)

res, L, edge_pos = relrad_calc(cost_functions, network, conf)
IC_base = res["base"].CENS
ENS = res["base"].ENS
ENSt = res["temp"].ENS
ENS_sum = sum(ENS+ENSt;dims=2)

ENS_sum_target = [0.18; 0.94; 0.11; 0.86]
epsilon = sum(ENS_sum_target)*1/100 # [kWh]. I take 1% of expected total interrupted energy as maximum error in calculation
@test isapprox(sum(ENS_sum), sum(ENS_sum_target), atol=epsilon)

ENS = Dict("downstream" => [3, 0.05, 0.0375, 0.025],
           "upstream" => [0.0625, 0.05, 1.8, 1.2])
# Check upstream and downstream switch failure on line 3
for key in keys(ENS)
    @test isapprox(sum(res[key].ENS[:, 3]), sum(ENS[key]), atol=epsilon)
end

# Check communication failure
@test abs(sum(res["comm_fail"].ENS[:, 2]) - sum([0.02083, 0.8, 0.0125, 0.0083]))<epsilon
# Check reserve failure
@test abs(sum(res["reserve_trans_grid-T2"].ENS) - sum([2.10833, 2.48333, 1.265, 1.6267]))<epsilon

# Check if it works when we consider capacity
res, _, _ = relrad_calc(cost_functions, network)
ENS = res["base"].ENS
ENSt = res["temp"].ENS
ENS_sum = sum(ENS+ENSt;dims=2)

ENS_sum_target = [0.18; 2.54; 0.11; 0.86]
epsilon = sum(ENS_sum_target)*1/100 # [kWh]. I take 1% of expected total interrupted energy as maximum error in calculation
@test isapprox(sum(ENS_sum), sum(ENS_sum_target), atol=epsilon)

# Check if it works when we add a NFC
network.mpc.load[1, :nfc] = true
network = RadialPowerGraph(network.mpc)
res, _, _ = relrad_calc(cost_functions, network)

@test isapprox(sum(IC_base[2, :]), sum(res["base"].CENS[2, :]))
