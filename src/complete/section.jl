module section

import Base
import Graphs: connected_components
import MetaGraphsNext: labels, edge_labels, neighbor_labels
import MetaGraphsNext: haskey, setindex!, getindex, delete!

using Graphs: SimpleGraph, Graph
using MetaGraphsNext: MetaGraphsNext, label_for
using SintPowerCase: Case
using DataFrames: outerjoin, keys
using DataStructures: DefaultDict, Queue

using ..network_graph: Network, KeyType, is_supply, get_supply_power, get_load_power, get_nfc_load_power
using ..network_graph: Bus, is_switch, get_kile, NewBranch, NewSwitch
using ...RelDist: PieceWiseCost

"""Representation of the subgraph of the network that is supplied by a given bus.
Note: This is an implementation detail to `segment_network` and should not be used outside it."""
mutable struct NetworkPart
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

Base.hash(party::NetworkPart, h::UInt) = hash(party.subtree, h)
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
    parts::Vector{NetworkPart},
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
    parts::Vector{NetworkPart},
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
    any(nbr_idx -> !(nbr_idx in part.subtree), neighbor_labels(network, node_idx))
end

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
    cost_functions=DefaultDict{String,PieceWiseCost}(PieceWiseCost()),
    correction_factor=1.0,
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
    network[new_edge...] = network[old_edge...]
    # network[old_edge...] = missing
    delete!(network, old_edge...)
end

## Beginning of preprocessing
"""Transform the graph such that edges with no switches are removed and its vertices are combined.
Used as preprocessing to reduce the size of the graph and to avoid edge-cases where the search ends at
an edge that cannot be cut."""
function remove_switchless_branches!(network::Network)
    did_change = true
    while did_change
        did_change = false
        for edge in edge_labels(network)
            branch::NewBranch = network[edge...]
            if is_switch(branch) || edge[1] == edge[2]
                # We keep self-edges (for now)
                # If we want to remove them, we should do it below
                continue
            end
            did_change = true

            (node_a::KeyType, node_b::KeyType) = edge
            @info "removing $(edge)"
            bus_a::Bus = network[node_a]
            bus_b::Bus = network[node_b]
            append!(bus_a.loads, bus_b.loads)
            append!(bus_a.supplies, bus_b.supplies)
            for nbr in collect(neighbor_labels(network, node_b))
                old_edge = (nbr, node_b)
                new_edge = (nbr, node_a)
                move_edge!(network, old_edge, new_edge)
            end

            if haskey(network, node_b, node_b)
                move_edge!(network, (node_b, node_b), (node_a, node_a))
            end

            delete!(network, node_b)

            break
        end
    end
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
    parts::Vector{NetworkPart},
    cost_function::Function=energy_not_served,
)::Vector{NetworkPart}
    # Use the hashes as keys in the cache because its easier to debug
    # I'm annoyed i have to use Any when i know that the three Any types will always be the same
    cache::Dict{UInt,Tuple{Any,Vector{NetworkPart}}} = Dict()
    visit_count = 0
    cache_hits = 0
    start = time()

    function recurse(parts::Vector{NetworkPart})::Tuple{Any,Vector{NetworkPart}}
        # TODO: Remove when fast
        visit_count += 1
        if visit_count % 100000 === 0
            @info "" cache_size = length(cache) cache_hit_count = cache_hits cache_miss_count =
                visit_count time_spent = time() - start

            # elseif visit_count + cache_hits > 2e7
            #     return (0.0, Set())
        end

        choices::Vector{Tuple{Any,Vector{NetworkPart}}} = []

        for part in parts,
            node_label in part.leaf_nodes,
            neighbour_idx in neighbor_labels(network, node_label)
            # Check this part first because it's more likely
            if neighbour_idx in part.subtree ||
               any(neighbour_idx in part.subtree for part in parts)
                continue
            end
            local neighbour = network[neighbour_idx]
            if get_load_power(neighbour) > part.rest_power
                continue # Overload
            end

            visit!(network, parts, part, neighbour_idx)
            local hashy = hash(parts)
            local nested_result = if hashy in keys(cache)
                cache_hits += 1
                cache[hashy]
            else
                local dropped_leaves = clean_leaf_nodes!(network, part)
                local nested_result = recurse(parts)
                cache[hashy] = nested_result
                restore_leaf_nodes!(part, dropped_leaves)
                nested_result
            end
            push!(choices, nested_result)
            unvisit!(network, parts, part, neighbour_idx)
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

    res = recurse(parts)
    @info "" cache_size = length(cache) cache_hit_count = cache_hits cache_miss_count =
        visit_count time_spent = time() - start
    res[2]
end

function segment_network(network::Network, cost_function::Function=energy_not_served)
    supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
    parts = [NetworkPart(network, supply) for supply in supplies]
    segment_network(network, parts, cost_function)
end

## End of DFS in state space
## Beginning of classic reimpl

"""DFS over all buses from the start bus, gobbling up all nodes we can. 
TODO: If we encounter overload on a branch with no switch we return nothing to backtrack."""
function traverse_classic(network::Network, part::NetworkPart, off_limits=Set{KeyType}())
    visit = [part.subtree...]

    while !isempty(visit)
        v_src = pop!(visit)

        to_visit = setdiff(neighbor_labels(network, v_src), part.subtree)
        setdiff!(to_visit, off_limits)
        for v_dst in to_visit
            if get_load_power(network[v_dst]) > part.rest_power
                # TODO: Handle the case where the branch doesn't have any switches
                continue
            end
            visit!(network, part, v_dst)
            push!(visit, v_dst)
        end
    end
    part
end

function segment_network_classic(network::Network, parts::Vector{NetworkPart})
    all_supplied = Vector{NetworkPart}()
    for part in parts
        println("$part")
        supplied_by_this = traverse_classic(network, part)
        push!(all_supplied, supplied_by_this)
    end

    # Handle overlaps

    all_supplied
end

function segment_network_classic(network::Network)
    supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
    parts = [NetworkPart(network, supply) for supply in supplies]
    segment_network_classic(network, parts)
end

"""Get the union of all other """
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

"""Get a good start point for the complete search using the data 
from the `segment_network_classic` algorithm"""
function get_start_guess(network::Network, old_parts::Vector{NetworkPart})
    supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
    parts = [NetworkPart(network, supply) for supply in supplies]
    all_supplied = Vector{NetworkPart}()
    for (old_part, part) in zip(old_parts, parts)
        println("$part")
        off_limits = get_off_limits(old_part, old_parts)
        supplied_by_this = traverse_classic(network, part, off_limits)
        push!(all_supplied, supplied_by_this)
    end
    all_supplied
end
## End of classic reimpl

## Beginning of bubble segment
"""Segment network by growing bubbles that collide like soap bubbles"""
function bubble_segment(network::Network, parts::Vector{NetworkPart})
    queues = [Queue{KeyType}(part.subtree) for part in parts]
    # Step 1: Grow bubble doing one step per part until they can't grow anymore
    #   They cannot overlap, nor can they take more load than they can handle
    #   Bubbles should grow in a BFS manner
    # Step 2: At each border between two parts, part A and B
    #   If:
    #       A has unsupplied neighbours
    #       B has the capacity to handle the load
    #       Losing the load won't split a
    #   Or (considered later):
    #       A has unsupplied nfc loads
    #       and the other conditions from above
    #   Then:
    #       Move the load from A to b
    #       Go to step 1
    #   Else:
    #       Quit

    # How to handle handoff of nodes that might cause an island to be created?
    # I don't think it's possible

    while true # While we have some gains
        # TODO: Try this if you have spare time
    end
end

function bubble_segment(network::Network)
    supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
    parts = [NetworkPart(network, supply) for supply in supplies]
    bubble_segment(network, parts)
end

## End of bubble segment

## Beginnning of coarsen segment
"""Segment network by first coarsening the network, segmenting and then refining the solution"""
function coarsen_segment(network::Network, parts::Vector{NetworkPart})
    queues = [Queue{KeyType}(part.subtree) for part in parts]
    # Step 1: Coarsen network by combining adjacent nodes
    # Step 2: Create parts on this network
    # Step 3: Convert parts to the finer network
    # Step 4: Refine the solution

    # Edge case: What if the course solution goes too far in the wrong direction

    while true # While we have some gains
        # TODO: Try this if you have spare time
    end
end

function coarsen_segment(network::Network)
    supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
    parts = [NetworkPart(network, supply) for supply in supplies]
    bubble_segment(network, parts)
end
## End of coarsen segment 

end # module section
