using RelDist
using SintPowerGraphs
using DataFrames

network_filename = joinpath(@__DIR__, "CINELDI.toml")
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)

network = RadialPowerGraph(network_filename)

# The names in the CINELDI dataframe are not the same as what is expected.
rename!(network.mpc.reldata, :r_perm => :repairTime)
rename!(network.mpc.reldata, :r_temp => :temporaryFaultTime)
rename!(network.mpc.reldata, :lambda_perm => :permanentFaultFrequency)
rename!(network.mpc.reldata, :lambda_temp => :temporaryFaultFrequency)

rename!(network.mpc.reldata, :sectioning_time => :sectioningTime)

# Add switch data for the smart healing stuff
network.mpc.switch[!, :t_remote] .= 1/3600 # I set the remote switching time to 1 second
network.mpc.switch[!, :t_manual] .= 0.5 # I set the manual switching time to 30 minutes

# Code should read this
network.reserves = ["36", "62", "88"]

conf = RelDistConf(traverse=Traverse(consider_cap=false),
                   failures=Failures(switch_failures=true,
                                    communication_failure=true,
                                   reserve_failure=true))

res, L, edge_pos = relrad_calc(cost_functions, network, conf)

# resframe = ResFrames(res, rest, edge_pos, L)

