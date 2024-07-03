using Graphs: SimpleGraph, Graph
import Graphs: connected_components
using MetaGraphsNext: MetaGraphsNext, label_for
import MetaGraphsNext: labels, edge_labels, neighbor_labels
import MetaGraphsNext: haskey, setindex!, getindex, delete!
using SintPowerCase: Case
using DataFrames: outerjoin, keys

import Base

### Bus

@enum BusKind t_supply t_load t_nfc_load
struct SupplyUnit
    power::Float64
end

struct LoadUnit
    power::Float64
    type::String # e.g. residental/industry
    correction_factor::Real
    is_nfc::Bool
end
struct Bus
    loads::Vector{LoadUnit}
    supplies::Vector{SupplyUnit}
end


"""Simple constructor to be compatible with previous versions of tests"""
function Bus(type::BusKind, power::Float64)
    if type == t_supply
        Bus([], [SupplyUnit(power)])
    elseif type == t_load
        Bus([LoadUnit(power, "residental", 1.0, false)], [])
    elseif type == t_nfc_load
        Bus([LoadUnit(power, "residental", 1.0, true)], [])
    end
end

function get_supply_power(bus::Bus)
    summy = 0.0
    for supply in bus.supplies
        summy += supply.power
    end
    summy
end

function get_load_power(bus::Bus)
    summy = 0.0
    for load in bus.loads
        if load.is_nfc
            continue
        end
        summy += load.power
    end
    summy
end

function get_nfc_load_power(bus::Bus)
    summy = 0.0
    for load in bus.loads
        if !load.is_nfc
            continue
        end
        summy += load.power
    end
    summy
end

# only for visualization
is_nfc(bus::Bus) = get_nfc_load_power(bus) > 0.0

function is_supply(bus::Bus)
    length(bus.supplies) !== 0
end

# Note: I will be making this assumption
is_load(bus::Bus) = !is_supply(bus)

### /Bus
### Branch

const KeyType = String

struct NewSwitch
    bus::KeyType
    is_closed::Bool
    switching_time::Float64
end

NewSwitch() = NewSwitch("you should have a key here if you're not testing code", false, 0.2)

struct NewBranch
    repair_time::Float64 # h
    switches::Vector{NewSwitch}
end

NewBranch() =
    NewBranch(0.5, [NewSwitch()])

function is_switch(branch::NewBranch)
    length(branch.switches) > 0
end

get_min_switching_time(branch::NewBranch) = minimum(s -> s.switching_time, branch.switches)

const VertexType = Bus
const EdgeType = NewBranch
struct Network
    network::MetaGraphsNext.MetaGraph{Int,SimpleGraph{Int},KeyType,VertexType,EdgeType}
    switching_time::Float64
end

# graf[label] = vertex
# graf[labe, label] = edge

function Network(switching_time::Float64=0.5)
    network = MetaGraphsNext.MetaGraph(
        Graph();
        label_type=KeyType,
        vertex_data_type=VertexType,
        edge_data_type=EdgeType,
    )
    Network(network, switching_time)
end

# Forwarding methods to the inner network
empty_network() = Network()
labels(network::Network) = labels(network.network)
edge_labels(network::Network) = edge_labels(network.network)
neighbor_labels(network::Network, key::KeyType) = neighbor_labels(network.network, key)
haskey(network::Network, key::KeyType) = haskey(network.network, key)
setindex!(network::Network, value::VertexType, key::KeyType) =
    setindex!(network.network, value, key)
getindex(network::Network, key::KeyType) = getindex(network.network, key)
setindex!(network::Network, value::EdgeType, key_a::KeyType, key_b::KeyType) =
    setindex!(network.network, value, key_a, key_b)
getindex(network::Network, key_a::KeyType, key_b::KeyType) =
    getindex(network.network, key_a, key_b)
delete!(network::Network, key::KeyType) =
    delete!(network.network, key)
delete!(network::Network, key_a::KeyType, key_b::KeyType) =
    delete!(network.network, key_a, key_b)

"""Create Network instances for each of the connected_components in the network"""
function connected_components(network::Network, switching_time::Float64=0.5)::Vector{Network}
    comps = []
    for subnet_indices in connected_components(network.network)
        subnet = Network(switching_time)
        subnet_labels = [label_for(network.network, idx) for idx in subnet_indices]
        [subnet[label] = network[label] for label in labels(network) if label in subnet_labels]
        [subnet[edge...] = network[edge...] for edge in edge_labels(network) if edge[1] in subnet_labels && edge[2] in subnet_labels]
        push!(comps, subnet)
    end
    comps
end

"""Representation of the subgraph of the network that is supplied by a given bus.
Note: This is an implementation detail to `segment_network` and should not be used outside it."""
mutable struct NetworkPart
    # TODO: Det er kanskje raskere om vi har et separat sett med leaf-nodes, 
    # så vi slepp å iterere over heile subtreet kvar iterasjon
    rest_power::Float64
    subtree::Set{KeyType}
    leaf_nodes::Set{KeyType}
end

function NetworkPart(network::Network, supply::KeyType)
    bus = network[supply]
    if !is_supply(bus)
        error("Parts should only be instantiated at power supplies")
    end
    subtree = Set([supply])
    leaf_nodes = Set([supply])
    NetworkPart(get_supply_power(bus), subtree, leaf_nodes)
end

Base.hash(party::NetworkPart) = hash((party.rest_power, party.subtree))
Base.:(==)(a::NetworkPart, b::NetworkPart) = hash(a) == hash(b)
Base.keys(party::NetworkPart) = Base.keys(party.subtree)

function visit!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power -= get_load_power(bus)
    push!(part.subtree, visitation)
    push!(part.leaf_nodes, visitation)
end

function unvisit!(network::Network, part::NetworkPart, visitation::KeyType)
    bus::Bus = network[visitation]
    part.rest_power += get_load_power(bus)
    pop!(part.subtree, visitation)
    pop!(part.leaf_nodes, visitation)
end

function visit!(
    network::Network,
    parts::Set{NetworkPart},
    part::NetworkPart,
    visitation::KeyType,
)
    # Warning: by modifying something in a set we open up the possibility for a lot of errors.
    # for example this following line will throw even though part is in parts
    # because part has been modified.
    # if !(part in parts)
    #     error("Part to visit must be in set of parts")
    # end
    # pop!(parts, part)
    visit!(network, part, visitation)
    # push!(parts, part)
end

function unvisit!(
    network::Network,
    parts::Set{NetworkPart},
    part::NetworkPart,
    visitisation::KeyType,
)
    # if !(part in parts)
    #     error("Part to unvisit must be in set of parts")
    # end
    # pop!(parts, part)
    unvisit!(network, part, visitisation)
    # push!(parts, part)
end

function is_leaf(network::Network, part::NetworkPart, node_idx::KeyType)::Bool
    for nbr_idx in neighbor_labels(network, node_idx)
        if !(nbr_idx in part.subtree)
            return true
        end
    end
    false
end

function clean_leaf_nodes!(network::Network, part::NetworkPart)::Vector{KeyType}
    removed::Vector{KeyType} = []
    for node_idx in part.leaf_nodes
        if !is_leaf(network, part, node_idx)
            push!(removed, node_idx)
        end
    end
    [pop!(part.leaf_nodes, r) for r in removed]
    removed
end

function restore_leaf_nodes!(part::NetworkPart, leaf_nodes::Vector{KeyType})
    [push!(part.leaf_nodes, l) for l in leaf_nodes]
end

"""Creates an iterator over all neighbours of all parts"""
function nodes_to_visit(network::Network, parts::Set{NetworkPart})
    buffer::Vector{Tuple{NetworkPart,KeyType}} = []
    for part in parts
        # For each of the node in the subtree
        for node_idx in part.leaf_nodes
            # For each of the neighbours of that node
            for neighbour_idx in neighbor_labels(network, node_idx)
                if any([neighbour_idx in part.subtree for part in parts])
                    # Either walking back in subtree or colliding with another subtree
                    # Anyways we don't want it
                    continue
                end
                push!(buffer, (part, neighbour_idx))
            end
        end
    end
    buffer
end


"""Check if a given vertex is served by any of the given network parts"""
function is_served(parts::Set{NetworkPart}, vertex::KeyType)
    for part::NetworkPart in parts
        if vertex in part.subtree
            return true
        end
    end
    return false
end


"""
Create a function that takes a set of parts given the captured network and repair time.
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
    repair_time::Float64=4.0,
    correction_factor=1.0,
    cost_functions=Dict("residental" => PieceWiseCost()),
)
    # TODO: switching time should be the highest of all the switces needed to isolate this part of the grid
    switching_time = 0.5
    function kile_internal(parts::Set{NetworkPart})::Float64
        cost = 0.0
        for vertex in labels(network)
            bus::Bus = network[vertex]
            time_spent = is_served(parts, vertex) ? switching_time : repair_time
            for load in bus.loads
                cost_function = cost_functions[load.type]
                IC =
                    calculate_kile(load.power, time_spent, cost_function, correction_factor)
                cost += IC
            end
        end
        cost
    end
    kile_internal
end

function unsupplied_nfc_loss(network::Network)
    function unsupplied_nfc_internal(parts::Set{NetworkPart})::Float64
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
                cost += get_nfc_load_power(bus)
            end
        end

        cost
    end
    unsupplied_nfc_internal
end

function energy_not_served(parts::Set{NetworkPart})::Float64
    sum([part.rest_power for part in parts])
end

"""
Recursively finds the optimal way to partition the network into parts. Returns the different parts of the network.
Assume the fault has been found and isolated.

Note: Supplying NFC loads is considered trivial and not done by this function. 

To optimise for both CENS and supplying NFC loads, i recommend creating a compound loss function using tuples. 
    (1, 0) < (1, 1) && (0, 100) < (1, 0) in julia

# Example 

```jldoctest
network = create_mock_network()
kile_fn = kile_loss(network)
nfc_fn = unsupplied_nfc_loss(network)
loss_fn(parts::Set{Part}) = (kile_fn(parts), nfc_fn(parts))
optimal_split = segment_network(network, loss_fn)
loss_fn(optimal_split)

# output

(4.5, 0.0)
```
"""
function segment_network(
    network::Network,
    parts::Set{NetworkPart},
    cost_function::Function=energy_not_served,
)::Set{NetworkPart}
    # Use the hashes as keys in the cache because its easier to debug
    # I'm annoyed i have to use Any when i know that the three Any types will always be the same
    cache::Dict{UInt,Tuple{Any,Set{NetworkPart}}} = Dict()
    visit_count = 0
    start = time()

    function recurse(parts::Set{NetworkPart})::Tuple{Any,Set{NetworkPart}}
        hashy = hash(parts)
        if hashy in keys(cache)
            return cache[hashy]
        end

        visit_count += 1
        if visit_count % 100000 === 0
            println(visit_count, " ", time() - start, " s")
        elseif visit_count > 2e6
            return (1.0, Set())
        end

        # We do know that if we don't drop any loads, the deeper search
        # is always better, but this is hard to implement in a readable manner
        # so we just check it
        choices::Vector{Tuple{Any,Set{NetworkPart}}} = []

        for (part, neighbour_idx) in nodes_to_visit(network, parts)
            local neighbour = network[neighbour_idx]
            if get_load_power(neighbour) > part.rest_power
                continue # Overload
            end

            visit!(network, parts, part, neighbour_idx)
            local dropped_leaves = clean_leaf_nodes!(network, part)
            local nested_result = recurse(parts)
            push!(choices, nested_result)
            restore_leaf_nodes!(part, dropped_leaves)
            unvisit!(network, parts, part, neighbour_idx)
        end

        res = if length(choices) == 0
            loss = cost_function(parts)
            (loss, deepcopy(parts))
        elseif length(choices) == 1
            choices[1]
        else
            argmin(c -> c[1], choices)
        end
        cache[hashy] = res
        res
    end # function recurse

    res = recurse(parts)
    println(visit_count, " ", time() - start, " s")
    res[2]
end

function segment_network(network::Network, cost_function::Function=energy_not_served)
    supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
    parts = Set([NetworkPart(network, supply) for supply in supplies])
    segment_network(network, parts, cost_function)
end

"""Create a super simple network to use in doctests
# Examples
```jldoctest
network = create_mock_network()
get_power(network["load_1"])

# output

1.0
```
"""
function create_mock_network()
    network = empty_network()
    network["bf"] = Bus(t_supply, 1.0)
    network["load_1"] = Bus(t_load, 1.0)
    network["load_2"] = Bus(t_load, 1.0)
    network["bf", "load_1"] = NewBranch()
    network["load_1", "load_2"] = NewBranch()
    network
end

#### BELOW SHOULD GO SOMEWHERE ELSE

function add_buses!(graphy::Network, case::Case)
    bus_withgen =
        outerjoin(case.bus, case.gen, on=:ID => :bus, renamecols="_bus" => "_gen")
    buses_joined =
        outerjoin(bus_withgen, case.load, on=:ID => :bus, renamecols="" => "_load")
    loads::Vector{LoadUnit} = []
    gens::Vector{SupplyUnit} = []
    prev_id::Union{String,Nothing} = nothing

    for bus in eachrow(buses_joined)
        if bus[:ID] != prev_id && prev_id !== nothing
            graphy[prev_id] = Bus(loads, gens)
            loads = []
            gens = []
        end
        prev_id = bus[:ID]

        if bus[:P_load] !== missing
            loady = LoadUnit(bus[:P_load], bus[:type_load], 1.0, bus[:nfc_load])
            push!(loads, loady)
        end
        if bus[:Pmax_gen] !== missing
            supplyy = SupplyUnit(bus[:Pmax_gen])
            push!(gens, supplyy)
        end
    end

    graphy[prev_id] = Bus(loads, gens)
end

function add_branches!(graphy::Network, case::Case)
    branch_withswitch = outerjoin(case.branch, case.switch, on=[:f_bus, :t_bus], renamecols="_branch" => "_switch")
    # Sort the branches such that (a->b) and (b->a) are immediately after each other
    permute!(branch_withswitch, sortperm([sort([row.f_bus, row.t_bus]) for row in eachrow(branch_withswitch)]))
    if :br_r_branch in names(branch_withswitch) # for compat with cineldi_simple
        rename!(branch_withswitch, :br_r_branch => :r_branch)
    end
    switches::Vector{} = []
    prev_id::Union{Tuple{String,String},Nothing} = nothing
    prev_r::Union{Float64,Nothing} = nothing

    for branch in eachrow(branch_withswitch)
        # (a->b) and (b->a) are the same branch
        cur_id = Tuple(sort([branch[:f_bus], branch[:t_bus]]))
        if cur_id != prev_id && prev_id !== nothing
            # Make sure nodes exist
            # push switch to edges
            branchy = NewBranch(prev_r, switches)
            graphy[prev_id[1], prev_id[2]] = branchy
            switches = []
        end
        prev_id = cur_id
        if branch[:r_branch] !== missing
            prev_r = branch[:r_branch]
        end

        if branch[:closed_switch] !== missing
            switchy = NewSwitch(branch[:f_bus], branch[:closed_switch], branch[:t_remote_switch])
            push!(switches, switchy)
        end
    end

    branchy = NewBranch(prev_r, switches)
    graphy[prev_id[1], prev_id[2]] = branchy
end

Network(case_file::String) = Network(Case(case_file))
function Network(case::Case)
    graphy = empty_network()
    add_buses!(graphy, case)
    add_branches!(graphy, case)
    graphy
end

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
function find_isolating_switches(network::Network, to_visit::Vector{KeyType}, seen::Set{KeyType})
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
    min_switching_time = 0.0
    if (switch_to_cut = get_cutoff_switch(network, edge, node_a)) !== nothing
        # Special case where we must cut this switch
        min_switching_time = max(switch_to_cut.switching_time, min_switching_time)
    else
        # recurse to find minimum edge set
        local (edges, nodes) = find_isolating_switches(network, [node_a], Set([node_b]))
        union!(edges_to_rm, edges)
        union!(nodes_to_rm, nodes)
        push!(nodes_to_rm, node_a)
    end
    if (switch_to_cut = get_cutoff_switch(network, edge, node_b)) !== nothing
        # Special case where we must cut other switch
        min_switching_time = max(switch_to_cut.switching_time, min_switching_time)
    else
        # recurse to find minimum edge set
        local (edges, nodes) = find_isolating_switches(network, [node_b], Set([node_a]))
        union!(edges_to_rm, edges)
        union!(nodes_to_rm, nodes)
        push!(nodes_to_rm, node_b)
    end

    branches_to_cut = [edge for edge in edges_to_rm if !(edge[1] in nodes_to_rm) || !(edge[1] in nodes_to_rm)]
    switching_times = [get_min_switching_time(network[branch...]) for branch in branches_to_cut]

    [delete!(network, edge...) for edge in edges_to_rm]
    [delete!(network, node) for node in nodes_to_rm]

    (max(min_switching_time, maximum(switching_times)), branches_to_cut)
end

function relrad_calc_2(network::Network)
    for edge in edge_labels(network)
        edge = ("mf", "load")
        @info "handling edge $edge"
        # Shadow old network to not override by accident
        let network = deepcopy(network)
            repair_time = network[edge...].repair_time
            (node_a, node_b) = edge
            (isolation_time, cuts_to_make_irl) = isolate_and_get_time!(network, edge)

            for subnet in connected_components(network, isolation_time)
                kile_fn = kile_loss(subnet)
                nfc_fn = unsupplied_nfc_loss(subnet)
                # loss_fn(parts::Set{Part}) =
                optimal_split = segment_network(subnet, parts -> (kile_fn(parts), nfc_fn(parts)))
                loss = kile_fn(optimal_split)
                println(loss)
            end

            return network
        end
    end
end

