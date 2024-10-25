using RelDist
using RelDist: sort, LoadUnit
using SintPowerCase
using DataFrames
using Accessors: @reset
using Debugger

network_filename = joinpath(@__DIR__, "CINELDI.toml")
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)

case = Case(network_filename)

network = Network(case)
network_c, edge_mapping = remove_switchless_branches(network)

edge = [k for (k, v) in edge_mapping if ("10", "7") ∈ v][1]

(isolation_time, _cuts_to_make_irl) = isolate_and_get_time!(network_c, edge)
optimal_split_orig = segment_network_classic(network_c)
loads_orig, nfc_orig, shed_orig = get_loads_nfc_and_shed(network_c, optimal_split_orig[4])

# Add a battery on bus 25
case.gen.E .= Inf
temp_gen = DataFrame(case.gen[end, :])
temp_gen.bus .= "25"
temp_gen.ID .= "B1"
temp_gen.external .= false
temp_gen.E .= 2
temp_gen.Pmax .= 1

case.gen = vcat(case.gen, temp_gen)
network = Network(case)
network_c, edge_mapping = remove_switchless_branches(network)

colnames = [load.id for lab in labels(network_c) for load::LoadUnit in network_c[lab].loads]
ncols = length(colnames)
nrows = length(edge_labels(network_c))
vals = fill(1337.0, (nrows, ncols))
outage_times = DataFrame(vals, colnames)
outage_times[!, :cut_edge] = collect(map(sort, edge_labels(network_c)))


edge = [k for (k, v) in edge_mapping if ("10", "7") ∈ v][1]

edge_idx = findall(x -> x == edge, outage_times[:, :cut_edge])[1]

repair_time = network_c[edge...].repair_time
[outage_times[edge_idx, colname] = repair_time for colname in colnames] # Worst case for this fault

(isolation_time, _cuts_to_make_irl) = isolate_and_get_time!(network_c, edge)
optimal_split = @enter segment_network_classic(network_c)

loads, nfc, shed = get_loads_nfc_and_shed(network_c, optimal_split[4])

# @enter power_and_energy_balance!(
# network_c,
# optimal_split,
# isolation_time,
# repair_time,
# outage_times[edge_idx, :],
# )

# res = relrad_calc_2(network_c)
# mapped_res = empty(res)

# for row in eachrow(res)
# old_edges = edge_mapping[sort(row[:cut_edge])]
# for edge in old_edges
# mapped_row = copy(row)
# @reset mapped_row.cut_edge = edge
# push!(mapped_res, mapped_row)
# end
# end

# case.gen = vcat(case.gen, temp_gen)

# network = Network(case)

# t = compress_relrad(network)

# t = t[sortperm(t[:, :cut_edge]), :][:, sortperm(names(t))]
# res_b = transform_relrad_data(network, t, cost_functions)

# U = sum(sum(eachcol(res_b.U[:, 1:end-1])))
