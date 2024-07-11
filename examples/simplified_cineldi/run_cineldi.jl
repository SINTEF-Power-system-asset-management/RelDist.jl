using RelDist
using SintPowerCase
using SintPowerGraphs
using DataFrames

network_filename = joinpath(@__DIR__, "cineldi_simple.toml")
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)

case = Case(network_filename)
network = RadialPowerGraph(case)

# Just to make it a bit simpler to compare
network.mpc.switch.t_remote .= 0.5

# network.mpc.gen[2, :Pmax] = 13
# network.mpc.switch[12, :t_bus] = "NaN"
# network.mpc.switch[10, :t_bus] = "NaN"
# # Implement the fifth case from the power point
# network.mpc.switch[12, :f_bus] = "15"
# network.mpc.switch[12, :t_bus] = "16"
# network.mpc.load[1, :P] = 2.0
# network.mpc.load[1, :P] = 5.0
# network.mpc.load[10, :P] = 5.0
# network.mpc.load[1, :nfc] = true
network.mpc.switch.t_remote .= 0.5
network.mpc.gen[1, :Pmax] = 2
# Add batteries
i = 1
while i <=3
    append!(network.mpc.gen, DataFrame(network.mpc.gen[3,:]))
    network.mpc.gen[3+i, :ID] = string("DER", i)
    global i+=1
end
network.mpc.gen[4:6, :Pmax] = [2,3,4]
network.mpc.gen[4:6, :E] = [2,2,1]
network.mpc.gen[4:6, :external] .= false
network = RadialPowerGraph(network.mpc)
res, L, edge_pos = relrad_calc(cost_functions, network)
results = ResFrames(res, edge_pos, L)


