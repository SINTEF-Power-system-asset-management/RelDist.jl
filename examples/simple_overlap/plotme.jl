using RelDist: Network, NetworkPart, dot_plot, to_dot, energy_not_served, is_supply, labels
using RelDist: remove_switchless_branches!, segment_network, relrad_calc_2, compress_relrad, transform_relrad_data
using RelDist: sort, edge_labels, isolate_and_get_time!, NewResult
using RelDist: read_cost_functions
using DataFrames: DataFrame, select, Not
using Accessors: @set
using FileIO
using CSV: CSV

network = Network(joinpath(@__DIR__, "simple_overlap.toml"))

####################################
# Manually doing stuff for figures #
####################################
plot = dot_plot(network; layout="neato")
display(plot)