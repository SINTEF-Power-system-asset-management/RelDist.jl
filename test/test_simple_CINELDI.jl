using SintPowerGraphs
using Test

network_filename = joinpath(@__DIR__, "../examples/simplified_cineldi/cineldi_simple.toml")
cost_filename = joinpath(@__DIR__, "../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)
network =  RadialPowerGraph(network_filename)

# Just to make it a bit simpler to compare
network.mpc.switch.t_remote .= 0.5

res, L, edge_pos = relrad_calc(cost_functions, network)

# Case 1 in the power point
@test isapprox(sum(res["base"].U[:, 15]), 0.418, atol=0.01)

# Case 2 in the power point. NOT! BF2 can aslo supply
# load 10. This is therefore not case 2. Check what the
# correct answer should be for this case.
@test isapprox(sum(res["base"].U[:, 2]), 0.333, atol=0.01)

# If we increase the power of the load at bus 10, we get
# case 2.
# get the same result as before.
network.mpc.load[1, :P] = 2.0
res, L, edge_pos = relrad_calc(cost_functions, network)
@test isapprox(sum(res["base"].U[:, 2]), 0.333, atol=0.01)

# If we delete the switch between 12 and 14 we should also get
# the same result as before.
network.mpc.load[1, :P] = 2.0
network.mpc.switch[12, :t_bus] = "NaN"
res, L, edge_pos = relrad_calc(cost_functions, network)
@test isapprox(sum(res["base"].U[:, 2]), 0.333, atol=0.01)

# Reset the network and try the third case
# This should also give the same results as before
network = RadialPowerGraph(network_filename)
network.mpc.gen[2, :Pmax] = 13
network.mpc.switch.t_remote .= 0.5
res, L, edge_pos = relrad_calc(cost_functions, network)
@test isapprox(sum(res["base"].U[:, 2]), 0.333, atol=0.01)

# Implement the fourth case from the power point
network = RadialPowerGraph(network_filename)
network.mpc.switch.t_remote .= 0.5
network.mpc.switch[12, :t_bus] = "NaN"
network.mpc.switch[10, :t_bus] = "NaN"
network = RadialPowerGraph(network.mpc)

res, L, edge_pos = relrad_calc(cost_functions, network)
@test isapprox(sum(res["base"].U[:, 2]), 0.547, atol=0.01)

# Implement the fifth case from the power point
network.mpc.switch[12, :f_bus] = "15"
network.mpc.switch[12, :t_bus] = "16"
network = RadialPowerGraph(network.mpc)

# Implement case 9a from power point presentation
network = RadialPowerGraph(network_filename)
network.mpc.switch.t_remote .= 0.5
network.mpc.load[1, :P] = 5.0
network.mpc.load[10, :P] = 5.0

res, L, edge_pos = relrad_calc(cost_functions, network)
λ = network.mpc.reldata[2, :permanentFaultFrequency]
isol = 6:9
U = λ*(sum(5*length(isol))+0.5*sum(length(setdiff(1:10, isol))))
@test isapprox(sum(res["base"].U[:, 2]), U, atol=0.01)

# Implement case 9b from power point presentation
network.mpc.load[1, :nfc] = true
network = RadialPowerGraph(network.mpc)
res, L, edge_pos = relrad_calc(cost_functions, network)
U -= 5*λ
@test isapprox(sum(res["base"].U[:, 2]), U, atol=0.01)
