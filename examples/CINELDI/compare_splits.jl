include(joinpath(@__DIR__, "set_up_cineldi.jl"))
case.gen[[2, 3, 4], :Pmax] .= 2
network = Network(case)
net_c, edge_mapping = remove_switchless_branches(network)
edge = ("10", "10")
(_, _cuts_to_make_irl) = isolate_and_get_time!(net_c, edge)
orig_split, splitting_times = segment_network_classic(net_c)

case.gen[[2, 3, 4], :Pmax] .= 3
network = Network(case)
net_c, edge_mapping = remove_switchless_branches(network)
edge = ("10", "10")
(_, _cuts_to_make_irl) = isolate_and_get_time!(net_c, edge)
split, splitting_times = segment_network_classic(net_c)
