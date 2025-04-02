module isolating

using ..network_graph: Network, KeyType, ne, is_supply, is_main_supply, neighbor_labels
using ..network_graph: label_for, nv, labels, NewSwitch, find_main_supply
using ..network_graph: find_supply_breaker_time
using ..section: sort
using Combinatorics: combinations, permutations
using MetaGraphsNext: edge_labels

"""
   Returns the edges of the network in a DFS order.
"""
function dfs_edges(network::Network, start::KeyType)
    edges = Vector{Tuple{KeyType,KeyType}}(undef, ne(network))
    seen = [start]
    # Keep track of where we are coming from when doing the search
    visit = [(start, dst) for dst in neighbor_labels(network, start)]
    i = 1
    while !isempty(visit)
        (src, dst) = pop!(visit)
        visit = vcat(
            visit,
            [
                (dst, new_dst) for
                new_dst in sort!(setdiff(collect(neighbor_labels(network, dst)), seen))
            ],
        )
        edges[i] = (src, dst)
        push!(seen, dst)
        i += 1
    end
    return edges
end


"""
    Method for finding the center of a tree. The method iteratitvely
    removes all leaves from the tree until only one or two vertices are
    left.
"""
function find_tree_center(network::Network, start::KeyType)
    let network = deepcopy(network)
        while true
            visit = [start]
            seen = []
            leaves = Set{KeyType}()
            while !isempty(visit)
                v = pop!(visit)
                neighbors = collect(neighbor_labels(network, v))
                # Self edges destroy the algorithm
                if v ∈ neighbors
                    delete!(network, v, v)
                    neighbors = collect(neighbor_labels(network, v))
                end

                if length(neighbors) == 1
                    push!(leaves, v)
                end
                push!(seen, v)
                visit = vcat(visit, setdiff(neighbors, seen))
            end
            if length(seen) <= 2
                return seen
            end
            [delete!(network, leaf) for leaf in leaves]
            # Choose a starting point that is not a leaf
            start = setdiff(seen, leaves)[1]
        end
    end
end

function find_tree_center(network::Network)
    find_tree_center(network, collect(labels(network))[1])
end

"""
Find fault indicators
"""
function find_fault_indicators(network::Network, start::KeyType)
    indicators = Vector{Tuple{KeyType,KeyType}}()
    seen = [start]
    visit = [(start, dst) for dst in neighbor_labels(network, start)]
    while !isempty(visit)
        (src, dst) = pop!(visit)
        indcs = network[src, dst].indicators
        if !isempty(indcs)
            push!(indicators, (src, dst))
        else
            # If we found an indicator we should stop the search
            visit = vcat(
                visit,
                [
                    (dst, new_dst) for new_dst in
                    sort!(setdiff(collect(neighbor_labels(network, dst)), seen))
                ],
            )
        end
        push!(seen, dst)
    end
    return indicators
end

function dfs(network::Network, start::KeyType, ignore::Vector{KeyType})
    seen = deepcopy(ignore)
    visit = [(start, dst) for dst in setdiff(neighbor_labels(network, start), seen)]
    while !isempty(visit)
        (src, dst) = pop!(visit)
        visit = vcat(
            visit,
            [
                (dst, new_dst) for
                new_dst in sort!(setdiff(collect(neighbor_labels(network, dst)), seen))
            ],
        )
        push!(seen, dst)
    end
    return seen
end

function find_vertices(
    network::Network,
    vertices::Vector{KeyType},
    start::KeyType,
    ignore::Vector{KeyType},
)
    seen = deepcopy(ignore)
    visit = [(start, dst) for dst in setdiff(neighbor_labels(network, start), seen)]
    while !isempty(visit)
        (src, dst) = pop!(visit)
        visit = vcat(
            visit,
            [
                (dst, new_dst) for
                new_dst in sort!(setdiff(collect(neighbor_labels(network, dst)), seen))
            ],
        )

        push!(seen, dst)
        if dst ∈ vertices
            return true, seen
        end
    end
    return false, seen
end

function find_vertices(network::Network, vertices::Vector{KeyType}, start::KeyType)
    find_vertices(network, vertices, start, [start])
end

function find_edge(network::Network, edge::Tuple{KeyType,KeyType}, start::KeyType)
    find_vertices(network, collect(edge), start)
end

"""
This function checks if the the edge is between the feeder and the red_edge
if it is the feeder is updated. It also deletes one of the vertices in the
red_edge from the graph. This is used to reduce the search area after
operating a switch or due to fault indicators.
"""
function reduce_search_area!(
    network::Network,
    edge::Tuple{KeyType,KeyType},
    red_edge::Tuple{KeyType,KeyType},
    feeder::KeyType,
)
    for (dir, ignore) in permutations(collect(red_edge), 2)
        seen = dfs(network, dir, [ignore])
        if issubset(edge, seen[2:end])
            # We found the direction of the fault.
            # Now we have to check if the feeder is in this direction.
            if feeder ∉ seen[2:end]
                # The feeder and the fault are not in the same direction.
                # We cleared the fault and can update what we use as the
                # feeder
                feeder = dir
            end
            # We know the direction of the fault and can delete vertices
            # that are in the oposite direction.
            delete!(network, ignore)
            return feeder
        end
    end
    return feeder
end


"""
    Find the time needed to isolate a fault using binary search.
"""
function binary_fault_search(
    network::Network,
    edge::Tuple{KeyType,KeyType},
    feeder::KeyType,
    t_f::Real,
)
    tₛ = 0
    attempts = 0
    n_edges = ne(network)
    let network = deepcopy(network)
        indicator_edges = find_fault_indicators(network, edge[1])
        # We know that the fault will be between the indicators so we remove the
        # indicators from the graph
        for indicator_edge in unique(indicator_edges)
            if Set(indicator_edge) == Set(edge)
                # There are indicators on both sides of the edge where the fault is
                # we are done
                tₛ += findmin([s.switching_time for s in network[edge...].switches])[1]

                return (tₛ + t_f, attempts)
            end
            # Check if there is one indicator on the faulted edge
            indicator_handled = false
            if indicator_edge ∉ edge_labels(network)
                continue
            end
            indicators = network[indicator_edge...].indicators
            for i_bus in indicators
                if i_bus ∈ edge
                    indicator_handled = true
                    # One of the buses are on the faulted edge
                    # Delete all outgoing buses.
                    for nbr in neighbor_labels(network, i_bus)
                        if nbr ∉ edge
                            delete!(network, i_bus, nbr)
                            # Now we need to check if we should change the feeder bus
                            found, _ = find_vertices(network, [feeder], i_bus, [nbr])
                            if found
                                feeder = i_bus
                            end
                        end
                    end
                end
            end
            if !indicator_handled
                feeder = reduce_search_area!(network, edge, indicator_edge, feeder)
            end
        end

        switch = deepcopy(edge)
        while ne(network) > 1 || attempts < n_edges
            # Increase the isolation time with the time needed to operate the
            # circuit breaker of the feeder. 
            tₛ += t_f
            attempts += 1
            s_bus = find_tree_center(network, feeder)

            # Find all neighbors to the center vertex or the pair of center vertices
            switches = Vector{Tuple{KeyType,KeyType}}()
            nbrs = Vector{KeyType}()
            for src in s_bus
                nbr = collect(neighbor_labels(network, src))
                [push!(switches, (src, dst)) for dst in nbr if dst != src]
                nbrs = vcat(nbrs, nbr)
            end

            if length(unique(nbrs)) <= 2
                return (tₛ, attempts - 1)
            end

            # Now we have to choose the switch to operate.
            s_times = Vector{Real}(undef, length(switches))
            for (i, temp_s) in enumerate(switches)
                tmp = [s.switching_time for s in network[temp_s...].switches]
                s_times[i] = isempty(tmp) ? Inf : findmin(tmp)[1]
            end

            # I consider switches that have a switching time of 1 minute close
            # to each other as being just as fast.
            thr = 1 / 60 / 60
            min_times = findall(x -> abs(x - findmin(s_times)[1]) <= thr, s_times)

            # Check if only one switch is fastest
            if length(min_times) == 1
                switch = switches[min_times[1]]
                tₛ += s_times[min_times[1]]
            else
                # More than one switch was the fastest. We choose the one closest
                # to the feeder.
                found = false
                seen_length = -1
                l_i = 0
                for (i, s) in enumerate(switches[min_times])
                    found, seen = find_vertices(network, [feeder], s[1], setdiff(nbrs, s))
                    tmp_l = length(seen)
                    if seen_length < tmp_l
                        seen_length = tmp_l
                        l_i = i
                    end
                    if found
                        switch = s
                        tₛ += s_times[min_times[i]]
                        break
                    end
                end
                # Check if one of the fastest switches were closest to the feeder
                if !found
                    # None of the fastest switches were closest to the feeder.
                    # Choose the one that saw the most
                    switch = switches[l_i]
                end

            end

            # If we by chance chose the faulted edge as the switch to open
            # we will assume that the fault is downstream of our switch.
            if sort(switch) == edge
                # Opening this switch will clear the fault. This means that the fault
                # is downstream from our switch.
                # Now we need to find the direction that is downstream
                for (dir, ignore) in permutations(collect(switch), 2)
                    seen = dfs(network, dir, [ignore])
                    if feeder ∈ seen
                        # Delete the branches upstream of the switch.
                        for v in neighbor_labels(network, dir)
                            if v != ignore && v != dir
                                delete!(network, v)
                            end
                        end
                        feeder = dir
                        break
                    end
                end
            else
                # Now we have to check if the fault is upstream or downstream of the switch
                feeder = reduce_search_area!(network, edge, switch, feeder)
            end

        end
    end
    return (tₛ, attempts)
end

function calculate_all_isolating_times(network::Network)
    feeder = find_main_supply(network)
    feeder_time = find_supply_breaker_time(network, feeder)
    calculate_all_isolating_times(network, feeder, feeder_time)
end

function calculate_all_isolating_times(network::Network, feeder::KeyType, feeder_time::Real)
    times = Dict(
        sort(edge) => binary_fault_search(network, sort(edge), feeder, feeder_time)[1]
        for edge in edge_labels(network)
    )
    return times
end

# End of module
end
