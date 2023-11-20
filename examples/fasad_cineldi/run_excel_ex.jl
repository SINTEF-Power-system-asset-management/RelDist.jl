using RelDist
using SintPowerGraphs
using SintPowerCase


network_filename = joinpath(@__DIR__, "excel_test.toml")
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions_dummy.json")

cost_functions = read_cost_functions(cost_filename)

case = Case(network_filename)

network = RadialPowerGraph(case)

conf = RelDistConf(traverse=Traverse(consider_cap=false),
                   failures=Failures(switch_failures=true,
                                    communication_failure=true,
                                   reserve_failure=true))
res, L, edge_pos = relrad_calc(cost_functions, network, conf)

