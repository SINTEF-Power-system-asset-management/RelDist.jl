using RelDist
using SintPowerCase
using SintPowerGraphs
using DataFrames

network_filename = joinpath(@__DIR__, "CINELDI.toml")
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)

case = Case(network_filename)

# Changes to the switches have to be done before creating the graph
# I used to have functions for syncing the graph and the case. 
# I should fix this later.

# Remove weird switches and add switches according to presentation
deleteat!(case.switch, 4:53)

# Add switch data for the smart healing stuff
case.switch[!, :t_remote] .= 0.5 #1/3600 # I set the remote switching time to 1 second
case.switch[!, :t_manual] .= 0.5 # I set the manual switching time to 30 minutes

# switches in the presentaiton
switches = [("26", "33"), ("33", "34"), ("33", "37"),
            ("46", "47"), ("47", "49"), ("47", "48"),
            ("85", "86"), ("86", "87"), ("86", "89"), ("86", "91"), ("86", "92")]
f_buses = [s[1] for s in switches]
t_buses = [s[2] for s in switches]
ns = length(f_buses)
append!(case.switch,
        DataFrame(f_bus=f_buses, t_bus=t_buses,
                  breaker=zeros(Bool, ns), closed=ones(Bool, ns),
                  t_remote=0.5*ones(ns), t_manual=0.5*ones(ns)))
# Add open switches at the reserve connections
switches = [("36", "35"), ("62", "61"), ("88", "87")]
f_buses = [s[1] for s in switches]
t_buses = [s[2] for s in switches]
ns = length(f_buses)
append!(case.switch,
        DataFrame(f_bus=f_buses, t_bus=t_buses,
                  breaker=zeros(Bool, ns), closed=zeros(Bool, ns),
                  t_remote=0.5*ones(ns), t_manual=0.5*ones(ns)))


network = RadialPowerGraph(case)

# The names in the CINELDI dataframe are not the same as what is expected.
rename!(network.mpc.reldata, :r_perm => :repairTime)
rename!(network.mpc.reldata, :r_temp => :temporaryFaultTime)
rename!(network.mpc.reldata, :lambda_perm => :permanentFaultFrequency)
rename!(network.mpc.reldata, :lambda_temp => :temporaryFaultFrequency)

rename!(network.mpc.reldata, :sectioning_time => :sectioningTime)


# Code should read this
network.reserves = ["36", "62", "88"]
# network.reserves = ["62"]

# # remote_switches = [("40", "37"),
                   # # ("46", "47"),
                   # # ("80", "81")]
# # s = network.mpc.switch
# # for switch in remote_switches
    # # s[s.f_bus.==switch[1] .&& s.t_bus.==switch[2], :t_remote] .= 1/3600
# # end
# #
network.mpc.switch[!, :t_remote] .= 1/3600

conf = RelDistConf(traverse=Traverse(consider_cap=false),
                   failures=Failures(switch_failure_prob=0.001,
                                    communication_failure_prob=0.00,
                                   reserve_failure_prob=0.00))

# # conf = RelDistConf(traverse=Traverse(consider_cap=true),
                   # # failures=Failures(switch_failure_prob=0.01,
                                    # # communication_failure_prob=0.01,
                                   # # reserve_failure_prob=0.01))

res, L, edge_pos = relrad_calc(cost_functions, network, conf)
results = ResFrames(res, edge_pos, L)


