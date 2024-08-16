module reldist

using Graphs: SimpleGraph, Graph
import Graphs: connected_components
using MetaGraphsNext: MetaGraphsNext, label_for
import MetaGraphsNext: labels, edge_labels, neighbor_labels
import MetaGraphsNext: haskey, setindex!, getindex, delete!
using SintPowerCase: Case
using DataFrames: DataFrame, outerjoin, keys, Not, select, nrow, select!
using DataStructures: DefaultDict, Queue
using Accessors: @set, @reset

import Base

using ..network_graph:
    Network, KeyType, LoadUnit, NewSwitch, NewBranch, time_to_cut, get_min_cutting_time
using ..network_graph: is_switch, get_kile
using ..section: kile_loss, unsupplied_nfc_loss, segment_network, get_outage_time
using ..section: remove_switchless_branches, sort
using ...RelDist: PieceWiseCost

# Terrible names
Edge = Tuple{KeyType,KeyType}
Base = String
Key = Union{Edge,Base}
CaseDict = DefaultDict{Key,Dict{String,Float64}}
TimeDict = DefaultDict{Edge,CaseDict}

"""Get the switch to cut off the given node from the given edge.
Assumes the node is on the edge"""
function get_cutoff_switch(network::Network, edge::Tuple{KeyType,KeyType}, node::KeyType)
    for switch::NewSwitch in network[edge...].switches
        if switch.bus == node
            return switch
        end
    end
    nothing
end

"""Finds the switches and buses that are impossible to separate from a fault on an edge
# Example
If the fault is on edge :a -> :b and there is a switch on the :a side
```jl
(switches, buses) = find_isolating_switches(network, [:b], Set([:a]))
```
will find the correct switches and buses to remove. 
If there are no switches on any side just call the function twice, one for each direction.
"""
function find_isolating_switches(
    network::Network,
    to_visit::Vector{KeyType},
    seen::Set{KeyType},
)
    isolating_switches::Set{Tuple{KeyType,KeyType}} = Set()
    isolating_buses::Set{KeyType} = Set()
    while !isempty(to_visit)
        node = pop!(to_visit)
        push!(seen, node)

        for neighbor in setdiff(neighbor_labels(network, node), seen)
            if is_switch(network[node, neighbor])
                push!(seen, neighbor)
                push!(isolating_switches, (node, neighbor))
                push!(isolating_buses, node)
                continue
            end

            push!(to_visit, neighbor)
        end
    end
    return isolating_switches, isolating_buses
end

"""Removes the damaged nodes and edges from the network and returns the time it takes to do so.
Also returns the proverbial minimum cut for easier debugging.

#Example
```
(isolation_time, cuts_to_make_irl) = isolate_and_get_time!(network, faulty_edge)
# network is now modified
```
"""
function isolate_and_get_time!(network::Network, edge::Tuple{KeyType,KeyType})
    (node_a, node_b) = edge
    edges_to_rm = Set([edge])
    nodes_to_rm::Set{KeyType} = Set()
    min_switching_time = -Inf

    for (first, last) in [node_a => node_b, node_b => node_a]
        if (switch_to_cut = get_cutoff_switch(network, edge, first)) !== nothing
            # Special case where we must cut this switch
            min_switching_time = max(time_to_cut(switch_to_cut), min_switching_time)
        else
            # recurse to find minimum edge set
            local (edges, nodes) = find_isolating_switches(network, [first], Set([last]))
            union!(edges_to_rm, edges)
            union!(nodes_to_rm, nodes)
            push!(nodes_to_rm, first)
        end
    end

    # The only branches we need to cut are the ones that exit the bunch of affected nodes
    branches_to_cut = [
        edge for
        edge in edges_to_rm if !(edge[1] in nodes_to_rm) || !(edge[2] in nodes_to_rm)
    ]
    switching_times =
        [get_min_cutting_time(network[branch...]) for branch in branches_to_cut]
    switching_time = maximum(switching_times; init=min_switching_time)

    [delete!(network, edge...) for edge in edges_to_rm]
    [delete!(network, node) for node in nodes_to_rm]

    (switching_time, branches_to_cut)
end

function relrad_calc_2(network::Network)
    # edge_fault => { base | other_edge_fault => { load => time } }
    outage_times = TimeDict(CaseDict(Dict))
    all_loads = [load.id for lab in labels(network) for load::LoadUnit in network[lab].loads]

    for edge in edge_labels(network)
        # Shadow old network to not override by accident
        _network = deepcopy(network)
        repair_time = _network[edge...].repair_time
        [outage_times[edge]["base"][load] = repair_time for load in all_loads] # Worst case for this fault
        (isolation_time, _cuts_to_make_irl) = isolate_and_get_time!(_network, edge)

        for subnet in connected_components(_network, isolation_time, repair_time)
            kile_fn = kile_loss(subnet)
            nfc_fn = unsupplied_nfc_loss(subnet)
            optimal_split = segment_network(
                subnet;
                loss_function=parts -> (kile_fn(parts), nfc_fn(parts)),
            )

            for vertex in labels(subnet)
                for load::LoadUnit in subnet[vertex].loads
                    outage_times[edge]["base"][load.id] = get_outage_time(subnet, optimal_split, vertex)
                end
            end
        end

        # Switch malfunctions
        for failing_switch in _cuts_to_make_irl
            _network = deepcopy(network)
            branch = _network[failing_switch...]
            if length(branch.switches) > 1
                # Short circuit and just copy the base case results
                outage_times[edge][failing_switch] = outage_times[edge]["base"]
                continue
            end
            _network[failing_switch...] = @set branch.switches = []
            repair_time = _network[edge...].repair_time
            [outage_times[edge][failing_switch][load] = repair_time for load in all_loads] # Worst case for this fault
            (isolation_time, _cuts_to_make_irl) = isolate_and_get_time!(_network, edge)

            for subnet in connected_components(_network, isolation_time, repair_time)
                kile_fn = kile_loss(subnet)
                nfc_fn = unsupplied_nfc_loss(subnet)
                optimal_split = segment_network(
                    subnet;
                    loss_function=parts -> (kile_fn(parts), nfc_fn(parts)),
                )

                for vertex in labels(subnet)
                    for load::LoadUnit in subnet[vertex].loads
                        outage_times[edge][failing_switch][load.id] = get_outage_time(subnet, optimal_split, vertex)
                    end
                end
            end

        end
    end

    for vertex in labels(network)
        for load::LoadUnit in network[vertex].loads
            if load.is_nfc
                delete!(outage_times, load.id)
            end
        end
    end

    outage_times
end


function compress_relrad(network::Network)
    compressed_network, edge_mapping = remove_switchless_branches(network)
    times::TimeDict = relrad_calc_2(compressed_network)
    mapped_times = empty(times)

    for (edge, row) in times
        old_edges = edge_mapping[sort(edge)]
        for edge in old_edges
            mapped_row = copy(row)
            @reset mapped_row.cut_edge = edge
            push!(mapped_times, mapped_row)
        end
    end
    mapped_times
end

"""Get power data on the same format as the times df."""
function power_matrix(network::Network, times::DataFrame)
    power_df = copy(times)
    for row in eachrow(power_df)
        # Loads that are both in the df and the network
        for vertex in labels(network), load in network[vertex].loads
            if !(load.id in names(power_df))
                continue
            end
            row[load.id] = load.power
        end
    end
    power_df
end

"""Get fault_rate data on the same format as the times df."""
function fault_rate_matrix(network::Network, times::DataFrame)
    fault_rate_df = copy(times)
    for row in eachrow(fault_rate_df)
        # Loads that are both in the df and the network
        for vertex in labels(network), load in network[vertex].loads
            if !(load.id in names(fault_rate_df))
                continue
            end
            edge = row[:cut_edge]
            branch::NewBranch = network[edge...]
            fault_rate = branch.permanent_fault_frequency
            row[load.id] = fault_rate

        end
    end
    fault_rate_df
end

function cens_matrix(
    network::Network,
    times::DataFrame,
    cost_functions=DefaultDict{String,PieceWiseCost}(PieceWiseCost()),
    correction_factor=1.0,
)
    cens_df = copy(times)
    for row_idx = 1:nrow(cens_df)
        row = cens_df[row_idx, :]
        # Loads that are both in the df and the network
        for vertex in labels(network), load in network[vertex].loads
            if !(load.id in names(cens_df))
                continue
            end
            row[load.id] = load.power
            t = times[row_idx, load.id]
            kile = get_kile(load, t, cost_functions, correction_factor)
            row[load.id] = kile
        end
    end
    cens_df
end

struct NewResult
    t::DataFrame
    power::DataFrame
    lambda::DataFrame
    U::DataFrame
    ENS::DataFrame
    CENS::DataFrame
end

function transform_relrad_data(
    network::Network,
    times::DataFrame,
    cost_functions=DefaultDict{String,PieceWiseCost}(PieceWiseCost()),
    correction_factor=1.0,
)
    # Generate empty dataframe with proper shape
    # colnames = [load.id for lab in labels(network) for load::LoadUnit in network[lab].loads]
    # ncols = length(colnames)
    # nrows = length(edge_labels(network))
    # vals = fill(1337.0, (nrows, ncols))
    # outage_times = DataFrame(vals, colnames)
    # outage_times[!, :cut_edge] = collect(map(sort, edge_labels(network)))

    # To get times, we should use the compressed network. For everything else we can use the original
    power = power_matrix(network, times)
    fault_rate = fault_rate_matrix(network, times)

    p = select(power, Not(:cut_edge))
    lambda = select(fault_rate, Not(:cut_edge))
    outage_time = select(times, Not(:cut_edge))

    interruption_duration = lambda .* outage_time
    energy_not_supplied = interruption_duration .* p
    cost_of_ens = cens_matrix(network, times, cost_functions, correction_factor)
    interruption_duration[!, :cut_edge] = times[:, :cut_edge]
    energy_not_supplied[!, :cut_edge] = times[:, :cut_edge]
    cost_of_ens[!, :cut_edge] = times[:, :cut_edge]

    NewResult(
        times,
        power,
        fault_rate,
        interruption_duration,
        energy_not_supplied,
        cost_of_ens,
    )
end

end # module reldist
