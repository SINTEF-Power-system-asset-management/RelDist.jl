module section

import Base
import Base: sort!
import Graphs: connected_components
import MetaGraphsNext: labels, edge_labels, neighbor_labels
import MetaGraphsNext: haskey, setindex!, getindex, delete!
import Combinatorics: combinations

using Dates
using Graphs: SimpleGraph, Graph
using MetaGraphsNext: MetaGraphsNext, label_for
using SintPowerCase: Case
using DataFrames: outerjoin, keys, DataFrameRow
using DataStructures: DefaultDict, Queue
using Accessors: @set

using ..network_graph: Network, KeyType, is_supply, ne
using ..network_graph: Bus, is_switch, get_supply_power, get_load_power, get_nfc_load_power
using ..network_graph: NewBranch, NewSwitch, get_kile, LoadUnit, SupplyUnit
using ..network_graph: get_min_cutting_time
using ..network_part: NetworkPart, visit!, unvisit!, visit_and_shed!, is_leaf
using ..network_part: supply_in_island, all_loads_supplied
using ..network_part: get_loads_nfc_and_shed, get_part_der, visit_classic!, unvisit_classic!
using ..network_part: tot_load_in_parts
using ..battery: prepare_battery, visit_battery!, unvisit_battery!
using ...RelDist: PieceWiseCost


function clean_leaf_nodes!(network::Network, part::NetworkPart)::Vector{KeyType}
    removed =
        [node_idx for node_idx in part.leaf_nodes if !is_leaf(network, part, node_idx)]
    foreach(r -> pop!(part.leaf_nodes, r), removed)
    removed
end

function restore_leaf_nodes!(part::NetworkPart, leaf_nodes::Vector{KeyType})
    foreach(l -> push!(part.leaf_nodes, l), leaf_nodes)
end

"""Creates an iterator over all neighbours of all parts"""
function nodes_to_visit(network::Network, parts::Vector{NetworkPart})
    buffer::Vector{Tuple{NetworkPart,KeyType}} = []
    # For each of the node in the subtree
    # For each of the neighbours of that node
    for part in parts,
        node_label in part.leaf_nodes,
        neighbour_label in neighbor_labels(network, node_label)

        if any(neighbour_label in part.subtree for part in parts)
            # Either walking back in subtree or colliding with another subtree
            # Anyways we don't want it
            continue
        end
        push!(buffer, (part, neighbour_label))
    end
    buffer
end


"""Check if a given vertex is served by any of the given network parts"""
function is_served(parts::Vector{NetworkPart}, vertex::KeyType)
    any(part -> vertex in part.subtree, parts)
end

get_outage_time(network::Network, parts::Vector{NetworkPart}, vertex::KeyType) =
    is_served(parts, vertex) ? network.switching_time : network.repair_time

"""
Return the indices of the loads that can be served given a list of loads
and a capacity.
"""
function can_be_served(loads::Vector{<:Real}, capacity::Real)
    if isempty(loads)
        return [], [], 0.0
    end
    i = 0
    # Drop loads that are larger than the capacity.
    exceed_cap_idx = findfirst(>(capacity), loads)
    last_idx = isnothing(exceed_cap_idx) ? length(loads) : exceed_cap_idx

    while i <= last_idx
        P = sum(loads[1:last_idx-i])
        if P < capacity
            return 1:last_idx-i, last_idx-i+1:length(loads), P
        end
        i += 1
    end
    return [], 1:length(loads), 0
end

function set_outage_time!(loads::Vector{LoadUnit}, outage_times::DataFrameRow, time::Real)
    for load in loads
        outage_times[load.id] = time
    end
end

function serve_and_delete!(
    part::NetworkPart,
    loads::Vector{LoadUnit},
    ders::Vector{SupplyUnit},
    outage_times::DataFrameRow,
    repair_time::Real,
    isolation_time::Real,
)
    # First we check if any loads can be supplied by the feeder.
    served_idx, unserved_idx, power =
        can_be_served([load.power for load in loads], part.rest_power)
    part.rest_power -= power
    set_outage_time!(loads[served_idx], outage_times, isolation_time)
    deleteat!(loads, served_idx)

    serve_time = 0.0

    if isempty(ders)
        return
    end

    # Maximum time we may need a battery.
    t_m = repair_time - isolation_time

    # Then we have to check if batteries can help to serve load
    while !isempty(loads) && !isempty(ders)
        ratings = [der.power for der in ders]
        energies = [der.energy for der in ders]
        load_powers = [load.power for load in loads]
        capacity = part.rest_power + sum(ratings)
        served_idx, unserved_idx, to_be_served = can_be_served(load_powers, capacity)

        # Calculate how much power each DER should deliver based on the rating
        powers = (to_be_served - part.rest_power) / sum(ratings) .* ratings
        # Calcualte how long the DER can suppy the power and find the index of the
        # DER that will deplete first.
        times = energies ./ powers
        (min_time, min_time_idx) = findmin(times)
        # In case more than one battery has the same minimum time 
        # (unlikely in a realistic case)
        min_time_idx = findall(times .== min_time)

        if min_time >= t_m
            min_time = t_m
            # If min time is larger than t_m, it means that the loads in
            # this round can be served for the whole duration
            set_outage_time!(loads[served_idx], outage_times, isolation_time)
            # Delete the loads we could not serve
            deleteat!(loads, served_idx)
            unserved_idx = unserved_idx .- served_idx[end]
        end

        # Deplete the energy storages with the amount of energy they will serve
        # in this round
        for (der_i, energy) in enumerate(powers .* min_time)
            ders[der_i].energy -= energy
        end

        # Set the outage time for the loads we could not serve
        if to_be_served < sum(load_powers)
            set_outage_time!(loads[unserved_idx], outage_times, repair_time - serve_time)
            # Delete the loads we could not serve
            deleteat!(loads, unserved_idx)
        end

        serve_time += min_time
        if serve_time >= t_m
            return
        end
        if min_time < t_m
            # Delete the battery that was empty
            deleteat!(ders, min_time_idx)
        end
    end
    set_outage_time!(loads, outage_times, repair_time - serve_time)
    return
end


"""
Determine which loads can be reconnected considering spare capacity and
batterie
"""
function power_and_energy_balance!(
    network::Network,
    parts::Vector{NetworkPart},
    isolation_time::Real,
    repair_time::Real,
    outage_times::DataFrameRow,
)
    for part in parts
        loads, nfc, shed = get_loads_nfc_and_shed(network, part)

        # All loads that were served to begin with we set the outage time to
        # the isolation_time.
        set_outage_time!(loads, outage_times, isolation_time)
        ders = get_part_der(network, part)
        # Sort the lists
        shed = shed[sortperm([load.power for load in shed])]
        nfc = nfc[sortperm([load.power for load in nfc])]
        ders = ders[sortperm([sup.power for sup in ders])]

        serve_and_delete!(part, shed, ders, outage_times, repair_time, isolation_time)
        serve_and_delete!(part, nfc, ders, outage_times, repair_time, isolation_time)
    end
end



"""
Create a function that takes a list of parts given the captured network and repair time.
# Arguments
- `network::Network`: The network after the fault has been isolated.
- `repair_time::Float64`: The time to repair the fault.

# Examples
```jldoctest
network = create_mock_network()
loss_fn = kile_loss(network)
optimal_split = segment_network(network, loss_fn)
loss_fn(optimal_split)

# output

4.5
```
"""
function kile_loss(
    network::Network,
    repair_time::Float64 = 4.0,
    cost_functions = DefaultDict{String,PieceWiseCost}(PieceWiseCost()),
    correction_factor = 1.0,
)
    # TODO: switching time should be the highest of all the switches needed to isolate this part of the grid
    switching_time = network.switching_time
    function kile_internal(parts::Vector{NetworkPart})::Float64
        cost = 0.0
        for vertex in labels(network)
            bus::Bus = network[vertex]
            time_spent = is_served(parts, vertex) ? switching_time : repair_time
            for load in bus.loads
                cost += get_kile(load, time_spent, cost_functions, correction_factor)
            end
        end
        cost
    end
    kile_internal
end

function unsupplied_nfc_loss(network::Network)
    function unsupplied_nfc_internal(parts::Vector{NetworkPart})::Float64
        cost = 0.0

        for part in parts
            total_nfc_load = 0.0
            for idx in part.subtree
                load = get_nfc_load_power(network[idx])
                total_nfc_load += load
            end
            # For each part, get the amount of nfc load we cannot supply
            cost += max(0.0, total_nfc_load - part.rest_power)
        end

        for bus in labels(network)
            if !is_served(parts, bus)
                # Also get buses outside any subgraph, else it might be 
                # optimal to drop an nfc load that we might have partially served
                cost += get_nfc_load_power(network[bus])
            end
        end

        cost
    end
    unsupplied_nfc_internal
end

function energy_not_served(parts::Vector{NetworkPart})::Float64
    sum([part.rest_power for part in parts])
end

"""Moves an edge a->b to c->d."""
function move_edge!(
    network::Network,
    old_edge::Tuple{KeyType,KeyType},
    new_edge::Tuple{KeyType,KeyType},
)
    # Maybe todo: Handle the case where this edge already exists
    # Add the probabilities together, pick the max repair time
    # As long as we don't use them we don't really need this, we only need to keep the topology
    old_branch = network[old_edge...]
    indcs = old_branch.indicators
    new_indcs = Vector{KeyType}()
    nbr = intersect(new_edge, old_edge)[1]
    if indcs != [""]
        # The old edge has a fault indicator. Move it to the new edge.
        for ind in indcs
            if ind ∈ new_edge
                push!(new_indcs, ind)
            else
                push!(new_indcs, nbr)
            end
        end
    end
    new_indcs = unique(new_indcs)

    network[new_edge...] = network[old_edge...]
    network[new_edge...].indicators = new_indcs
    delete!(network, old_edge...)
end

const Edge = Tuple{KeyType,KeyType}
"""When moving edge a->b to a->c, add a mapping that says a->c => a->b.
To handle multiple edges becoming the same we use vector"""
function update_edge_mapping!(
    edge_mapping::Dict{Edge,Vector{Edge}},
    old_edge::Edge,
    new_edge::Edge,
)
    old_edges = pop!(edge_mapping, old_edge)

    if !(new_edge in keys(edge_mapping))
        edge_mapping[new_edge] = old_edges
    else
        append!(edge_mapping[new_edge], old_edges)
    end
end

## Beginning of preprocessing
"""This not being in the standard library is crazy"""
function sort(tuppy::Tuple{KeyType,KeyType})
    a, b = tuppy
    a < b ? (a, b) : (b, a)
end

"""When removing an edge, we ofen have to move another. Take the case:
a --- b []-- c => (ab) []-- c
Here we have to make sure that the switch between ab and c get the correct key, 
which is what this function does. 
"""
function fix_moved_switches!(network::Network, new_edge::Edge, from::KeyType, to::KeyType)
    branch::NewBranch = network[new_edge...]
    for switch_idx = 1:length(branch.switches)
        switch::NewSwitch = branch.switches[switch_idx]
        if switch.bus == from
            branch.switches[switch_idx] = @set switch.bus = to
        end
    end
end

# function fix_moved_indicators!(network::Network, new_edge::Edge, from::KeyType, to::KeyType)
# branch = network[new_edge...]
# for indicator in branch.indicators



"""Transform the graph such that edges with no switches are removed and its vertices are combined.
Used as preprocessing to reduce the size of the graph and to avoid edge-cases where the search ends at
an edge that cannot be cut."""
function remove_switchless_branches!(network::Network)
    edge_mapping = Dict(sort(edge) => [sort(edge)] for edge in edge_labels(network))
    did_change = true
    while did_change
        did_change = false
        for edge in sort!(collect(edge_labels(network)))
            branch::NewBranch = network[edge...]
            if is_switch(branch) || edge[1] == edge[2]
                # We keep self-edges (for now)
                # If we want to remove them, we should do it below
                continue
            end

            (node_a::KeyType, node_b::KeyType) = edge
            bus_a::Bus = network[node_a]
            bus_b::Bus = network[node_b]

            if is_supply(bus_a) && is_supply(bus_b) # TODO: Make sure renewables don't trigger this
                throw("Two supplies cannot be connected with no switch")
            end
            did_change = true

            append!(bus_a.loads, bus_b.loads)
            append!(bus_a.supplies, bus_b.supplies)
            for nbr in collect(neighbor_labels(network, node_b))
                old_edge = sort((nbr, node_b))
                new_edge = sort((nbr, node_a))
                move_edge!(network, old_edge, new_edge)
                update_edge_mapping!(edge_mapping, old_edge, new_edge)
                fix_moved_switches!(network, new_edge, node_b, node_a)
            end

            # It seemed to me that this code would not be necessary. I therefore
            # removed it.
            # if haskey(network, node_b, node_b)
            # old_edge = sort((node_b, node_b))
            # new_edge = sort((node_a, node_a))
            # move_edge!(network, old_edge, new_edge)
            # update_edge_mapping!(edge_mapping, old_edge, new_edge)
            # end

            delete!(network, node_b)

            break
        end
    end
    edge_mapping
end

function remove_switchless_branches(network::Network)
    newnet = deepcopy(network)
    edge_mapping = remove_switchless_branches!(newnet)
    newnet, edge_mapping
end

## End of preprocessing

## Beginning of DFS in state space
"""
Recursively finds the optimal way to partition the network into parts. Returns the different parts of the network.
Assume the fault has been found and isolated.

Note: Supplying NFC loads is considered trivial and not done by this function. 

To optimise for both CENS and supplying NFC loads, i recommend creating a compound loss function using tuples. 
(1, 0) < (1, 1) && (0, 100) < (1, 0) in julia

# Example 

```jl
network = create_mock_network()
kile_fn = kile_loss(network, 3.5)
nfc_fn = unsupplied_nfc_loss(network)
loss_fn(parts::Vector{NetworkPart}) = (kile_fn(parts), nfc_fn(parts))
optimal_split = segment_network(network, loss_fn)
loss_fn(optimal_split)

# output

(4.5, 0.0)
```
"""
function segment_network(
    network::Network,
    parts::Vector{NetworkPart};
    loss_function::Union{Function,Nothing} = nothing,
    off_limits = Set{KeyType}(),
)::Vector{NetworkPart}
    # prepare the clock
    start_time = now()
    iters = 0
    # Use the hashes as keys in the cache because its easier to debug
    # I'm annoyed i have to use Any when i know that the three Any types will always be the same
    cache::Dict{UInt,Tuple{Any,Vector{NetworkPart}}} = Dict()
    cost_function = if loss_function !== nothing
        loss_function
    else
        kile_fn = kile_loss(network)
        nfc_fn = unsupplied_nfc_loss(network)
        # Good default for the loss function
        parts::Vector{NetworkPart} -> (kile_fn(parts), nfc_fn(parts))
    end

    batteries, visited_batteries = prepare_battery(network)
    function recurse(
        parts::Vector{NetworkPart},
        visited_batteries::Vector{Bool},
    )::Tuple{Any,Vector{NetworkPart}}
        choices::Vector{Tuple{Any,Vector{NetworkPart}}} = []
        iters += 1
        if iters === 30_000
            time_spent = now() - start_time
            println(stderr, "$(canonicalize(time_spent))")
        elseif iters % 30_000 == 0
            time_spent = now() - start_time
            println(stderr, "\033[1A\r$(canonicalize(time_spent))")
        end

        for part in parts,
            node_label in part.leaf_nodes,
            neighbour_idx in neighbor_labels(network, node_label)

            # Check this part first because it's more likely
            if neighbour_idx in part.subtree ||
               any(neighbour_idx in part.subtree for part in parts)
                continue
            end
            if neighbour_idx in off_limits
                continue
            end
            local neighbour = network[neighbour_idx]

            # battery stuff must be done before checking for overload
            battery_result =
                visit_battery!(network, batteries, visited_batteries, part, neighbour_idx)
            if (battery_result === nothing) # I'm sorry for this mess :'(
                if get_load_power(neighbour) > part.rest_power
                    continue # Overload
                end
                visit!(network, parts, part, neighbour_idx)
            end
            local hashy = hash(parts)
            local nested_result = if hashy in keys(cache)
                cache[hashy]
            else
                local dropped_leaves = clean_leaf_nodes!(network, part)
                local nested_result = recurse(parts, visited_batteries)
                cache[hashy] = nested_result
                restore_leaf_nodes!(part, dropped_leaves)
                nested_result
            end
            push!(choices, nested_result)
            if battery_result !== nothing
                visited, bonus_power, battery_idx = battery_result
                unvisit_battery!(
                    network,
                    visited_batteries,
                    part,
                    visited,
                    bonus_power,
                    battery_idx,
                )
            else
                unvisit!(network, parts, part, neighbour_idx)
            end
        end

        res = if length(choices) == 0
            loss = cost_function(parts)
            (loss, deepcopy(parts))
        elseif length(choices) == 1 # TODO: Test if this is an actual speedup
            choices[1]
        else
            argmin(c -> c[1], choices)
        end
        res
    end # function recurse

    res = recurse(parts, visited_batteries)
    res[2]
end

function segment_network(network::Network; loss_function::Union{Function,Nothing} = nothing)
    supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
    parts = [NetworkPart(network, supply) for supply in supplies]
    segment_network(network, parts; loss_function = loss_function)
end

"""Traverse each part alone. This will leave overlaps."""
function segment_network_ignore_overlap(
    network::Network;
    loss_function::Union{Function,Nothing} = nothing,
)
    supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
    parts = [NetworkPart(network, supply) for supply in supplies]
    result_parts = Vector{NetworkPart}()
    for part in parts
        result_part = segment_network(network, [part]; loss_function = loss_function)
        push!(result_parts, result_part[1])
    end
    result_parts
end

"""Get a good start point for the complete search using the data 
from the `segment_network_classic` algorithm"""
function get_start_guess(
    network::Network,
    old_parts::Vector{NetworkPart};
    loss_function::Union{Function,Nothing} = nothing,
)
    supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
    parts = [NetworkPart(network, supply) for supply in supplies]
    all_supplied = Vector{NetworkPart}()
    for (old_part, part) in zip(old_parts, parts)
        off_limits = get_off_limits(old_part, old_parts)
        supplied_by_this = segment_network(
            network,
            [part];
            off_limits = off_limits,
            loss_function = loss_function,
        )
        push!(all_supplied, supplied_by_this[1])
    end
    all_supplied
end

"""Get the union of all other parts' subtrees"""
function get_off_limits(part::NetworkPart, parts::Vector{NetworkPart})
    off_limits = Set()
    for other_part in parts
        if other_part == part
            continue
        end
        union!(off_limits, other_part.subtree)
    end
    off_limits
end

"""Segment the network by finding the best set of loads for each part, backtracking the overlap
and then doing the segmentation from that starting point."""
function segment_network_fast(
    network::Network;
    loss_function::Union{Function,Nothing} = nothing,
)
    naive_parts = segment_network_ignore_overlap(network; loss_function = loss_function)
    start_guess = get_start_guess(network, naive_parts; loss_function = loss_function)
    segment_network(network, start_guess; loss_function = loss_function)
end
## End of DFS in state 
## Beginning of classic reimpl
#



"""DFS over all buses from the start bus, gobbling up all nodes we can. 
TODO: If we encounter overload on a branch with no switch we return nothing to backtrack."""
function traverse_classic!(
    network::Network,
    part::NetworkPart,
    visit::Vector{KeyType};
    off_limits = Set{KeyType}(),
    allow_shedding = false,
    dfs = true,
)
    while !isempty(visit)
        v_src = pop!(visit)

        to_visit = sort!(setdiff(neighbor_labels(network, v_src), part.subtree))
        setdiff!(to_visit, off_limits)
        for v_dst in to_visit
            if get_load_power(network[v_dst], consider_supply = false) > part.rest_power
                if allow_shedding
                    visit_and_shed!(network, part, v_dst)
                    if dfs
                        push!(visit, v_dst)
                    else
                        insert!(visit, 1, v_dst)
                    end
                else
                    # In case we have to stop the search in one direction, we should
                    # remember the location
                    push!(part.leaf_nodes, v_src)
                    continue
                end
            end

            if dfs
                push!(visit, v_dst)
            else
                insert!(visit, 1, v_dst)
            end
            visit_classic!(network, part, v_dst)
        end
    end
end

function traverse_classic!(
    network::Network,
    part::NetworkPart,
    v::KeyType;
    off_limits = Set{KeyType}(),
    allow_shedding = false,
    dfs = true,
)
    traverse_classic!(
        network,
        part,
        [v];
        off_limits = off_limits,
        allow_shedding = allow_shedding,
        dfs = dfs,
    )
end

function traverse_classic!(network::Network, part::NetworkPart; dfs = true)
    traverse_classic!(network, part, [part.supply], dfs = dfs)
end


"""
Check how much additional load can be suplied by a part after it has
been split from another part.
"""
function supply_after_split!(
    network::Network,
    part::NetworkPart,
    island::Vector{KeyType},
    off_limits::Set{KeyType},
)
    let part = deepcopy(part)
        # Remove the vertices not in the island
        for v in setdiff(part.subtree, island)
            unvisit_classic!(network, part, v)
            if v ∈ part.leaf_nodes
                pop!(part.leaf_nodes, v)
            end
        end
        # After the split  we traverse from all of the leaf nodes.
        # Note that the order of the leaf nodes may change the results,
        # but we will in any case do the search to the end later.
        traverse_leaves!(network, part, off_limits;)
        return part
    end
end

"""
Calls the traverse classic function from the leaves of a part, while not visiting
vertices in other parts.
"""
function traverse_leaves!(
    network::Network,
    part::NetworkPart,
    off_limits::Set{KeyType};
    allow_shedding = false,
)
    # Not sure if this is needed, but the loop will change part.leaf_nodes and I am
    # worried
    leaf_nodes = deepcopy(part.leaf_nodes)
    for v in leaf_nodes
        # Remove the leaf node from the list before we processes it.
        delete!(part.leaf_nodes, v)
        traverse_classic!(
            network,
            part,
            [v],
            off_limits = off_limits,
            allow_shedding = allow_shedding,
        )
        # Add the newly added vertices to the list of off limits vertices
        off_limits = union(part.subtree, off_limits)
    end
end


""" In case two parts overlap we have to find a switch to remove the overlap
this method takes care of that."""
function handle_overlap(
    network::Network,
    parts::Vector{NetworkPart},
    overlapping::Set{KeyType},
    off_limits::Set{KeyType},
    γ::Real = 1.0,
)
    best_parts = deepcopy(parts)
    island_idx = [0, 0]
    seen = Set{Tuple{KeyType,KeyType}}()
    best_p = Inf
    leaves_rest_w = 0.0
    best_edge = Tuple{KeyType,KeyType}
    # Iterate over all the buses that are in both parts
    for common in overlapping
        # Itereate over all the edges that are going out of the
        # common bus
        for neighbor in neighbor_labels(network, common)
            edge = sort((neighbor, common))
            if edge ∈ seen || neighbor == common
                continue
            end
            # Create a copy of the network and remove the edge
            let network = deepcopy(network)
                s_time = get_min_cutting_time(network[edge...])
                delete!(network, common, neighbor)
                islands = connected_components(network)
                if length(islands) == 1
                    # We have not added support for radial operation of
                    # meshed networks yet.
                    error("Meshed networks are not supported.")
                else
                    # We assume the edge splits the graph correctly
                    splits = true
                    for (part_id, part) in enumerate(parts)
                        island_idx[part_id] =
                            findall(map(x -> supply_in_island(part, x), islands))[1]
                    end
                    if island_idx[1] == island_idx[2]
                        # The edge did not split the graph correctly
                        splits = false
                    end
                    if splits
                        temp_parts = [
                            supply_after_split!(
                                network,
                                part,
                                islands[island_idx[part_id]],
                                off_limits,
                            ) for (part_id, part) in enumerate(parts)
                        ]
                        temp_p = sum(
                            part.rest_power *
                            (part.conn_time + s_time) *
                            (1 - γ * length(part.leaf_nodes)) for part in temp_parts
                        )
                        # temp_p = sum(
                        # part.rest_power + γ * length(part.leaf_nodes) for part in temp_parts
                        # )
                        if temp_p <= best_p
                            best_parts = temp_parts
                            best_p = temp_p
                            best_edge = (common, neighbor)
                        end
                    end
                end
            end
        end
    end
    if best_parts == parts
        throw("Could not split network")
    end
    off_limits = union(off_limits, union([part.subtree for part in best_parts]...))
    return best_parts, best_edge
end


function segment_network_classic(
    network::Network,
    parts::Vector{NetworkPart},
    γ::Real = 1.0,
)
    # First we check what the different parts can supply. In this step, we grow the parts
    # from the supply. In case one of the parts can supply everything we stop the search.
    for part in parts
        traverse_classic!(network, part, dfs = true)
        # If a part can supply all the loads we just return this part.
        if all_loads_supplied(network, part)
            return [part], 0.0
        end
    end
    # In case there was only one part we don't have to check for overlap
    if length(parts) == 1
        return [part], 0.0
    end

    # Create a list of vertices we have analysed
    off_limits = union([part.subtree for part in parts]...)

    splitting_times = zeros(length(parts))

    # After we have grown all the parts we have to check if any of them are 
    # overlapping.
    for comb_idx in combinations(1:length(parts), 2)
        overlapping = intersect(parts[comb_idx[1]], parts[comb_idx[2]])
        if length(overlapping) > 0
            # An old part is overlapping, we should handle this overlap.
            parts[comb_idx], split_edge =
                handle_overlap(network, parts[comb_idx], overlapping, off_limits, γ)
            cut_time = get_min_cutting_time(network[split_edge...])
            for time_idx in comb_idx
                splitting_times[time_idx] =
                    findmax([splitting_times[time_idx], cut_time])[1]
            end
        end
    end
    # We have handled the overlaps. Now we have to search all the way to the end
    # of the graph to find any renewables. We start the search from the part with the
    # highest capacity.
    for part in parts[sortperm([part.rest_power for part in parts], rev = true)]
        traverse_leaves!(network, part, off_limits, allow_shedding = true)
    end
    parts, splitting_times
end

function segment_network_classic(network::Network, γ::Real = 1.0)
    supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
    parts = [NetworkPart(network, supply) for supply in supplies]
    segment_network_classic(network, parts, γ)
end

## End of classic reimpl

end # module section
