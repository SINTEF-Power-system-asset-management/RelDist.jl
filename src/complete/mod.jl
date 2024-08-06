using Reexport

const Option{T} = Union{T,Nothing}

include("network_graph.jl")
@reexport using .network_graph: empty_network, Network, KeyType, labels, edge_labels
@reexport using .network_graph: t_load, t_battery, t_supply, t_nfc_load
@reexport using .network_graph: NewBranch, NewSwitch, is_switch
@reexport using .network_graph: Bus, BusKind, is_supply, is_battery, is_nfc, is_load
@reexport using .network_graph: branches, buses

include("network_part.jl")
@reexport using .network_part: NetworkPart
using .network_part: visit!, unvisit!, is_leaf

include("battery.jl")

include("section.jl")
@reexport using .section: segment_network_ignore_overlap, get_start_guess
@reexport using .section: segment_network, segment_network_fast, segment_network_classic
@reexport using .section: remove_switchless_branches!, remove_switchless_branches
@reexport using .section: kile_loss, energy_not_served
@reexport using .section: sort

include("from_case.jl")
@reexport using .from_case: Network
using .from_case: filter

include("reldist.jl")
@reexport using .reldist: relrad_calc_2, transform_relrad_data, compress_relrad

include("graphviz.jl")
@reexport using .graphviz_mod: to_dot, dot_plot
