using RelDist
using RelDist: sort, LoadUnit
using SintPowerCase
using DataFrames
using Accessors: @reset
using Debugger
using MetaGraphsNext: neighbor_labels

network_filename = joinpath(@__DIR__, "cineldi_simple.toml")
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)

case = Case(network_filename)

network = Network(case)
network_c, edge_mapping = remove_switchless_branches(network)

edge = [k for (k, v) in edge_mapping if ("2", "3") ∈ v][1]

(isolation_time, _cuts_to_make_irl) = isolate_and_get_time!(network_c, edge)
# optimal_split_orig = segment_network_classic(network_c)
