module isolating

using ..network_graph: Network, KeyType, ne, is_supply, is_main_supply, neighbor_labels
using ..network_graph: label_for, nv, labels, NewSwitch, find_main_supply
using ..network_graph: find_supply_breaker_time
using ..section: sort
using Combinatorics: combinations, permutations
using MetaGraphsNext: edge_labels

"""Helper function to delete edges adjacent to edge, except the edge itself"""
function delete_adjacent!(network::Network, src::KeyType, dst::KeyType)
    for v in neighbor_labels(network, src)
        if v != dst
            delete!(network, src, v)
        end
    end
end

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

function reduce_search_area!(
    network::Network,
    edge::Tuple{KeyType,KeyType},
    bus::KeyType,
    feeder::KeyType,
)
    for nbr in neighbor_labels(network, bus)
        if nbr ∉ edge
            # Now we need to check if we should change the feeder bus
            found, _ = find_vertices(network, [feeder], bus, [nbr])
            delete!(network, bus, nbr)
            if found
                feeder = bus
            end
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
            indicators = network[indicator_edge...].indicators
            if Set(indicators) == Set(edge)
                # There are indicators on both sides of the edge where the fault is
                # we are done
                tₛ += findmin([s.switching_time for s in network[edge...].switches])[1]

                return (tₛ + t_f, attempts)
            end
            # Check if there is one indicator on the faulted edge
            indicator_handled = false
            if indicator_edge ∉ edge_labels(network)
                # In case the edge we are investigating is not in the network we continue.
                # This can happen since we delete edges
                continue
            end
            for i_bus in indicators
                if i_bus ∈ edge
                    indicator_handled = true
                    # One of the buses are on the faulted edge
                    # Delete all outgoing buses.
                    feeder = reduce_search_area!(network, edge, i_bus, feeder)
                end
            end
            if !indicator_handled
                feeder = reduce_search_area!(network, edge, indicator_edge, feeder)
            end
        end

        switch = deepcopy(edge)
        while ne(network) > 1 && attempts < n_edges
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
            s_buses = Vector{String}(undef, length(switches))
            for (i, temp_s) in enumerate(switches)
                temp_switches = network[temp_s...].switches
                tmp_times = [s.switching_time for s in temp_switches]
                if isempty(tmp_times)
                    s_times[i] = Inf
                    s_buses[i] = ""
                else
                    s_times[i], j = findmin(tmp_times)
                    s_buses[i] = temp_switches[j].bus
                end
            end

            # I consider switches that have a switching time of 1 minute close
            # to each other as being just as fast.
            thr = 1 / 60 / 60
            min_times = findall(x -> abs(x - findmin(s_times)[1]) <= thr, s_times)

            # Check if only one switch is fastest
            if length(min_times) == 1
                switch = switches[min_times[1]]
                tₛ += s_times[min_times[1]]
                s_bus = s_buses[min_times[1]]
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
                        s_bus = s_buses[min_times[i]]
                        break
                    end
                end
                # Check if one of the fastest switches were closest to the feeder
                if !found
                    # None of the fastest switches were closest to the feeder.
                    # Choose the one that saw the most
                    switch = switches[l_i]
                    s_bus = s_buses[l_i]
                end
            end

            # In case the switch is on the faulted edge
            if s_bus ∈ edge
                feeder = reduce_search_area!(network, edge, s_bus, feeder)
            else
                feeder = reduce_search_area!(network, edge, switch, feeder)
            end

        end
    end
    if attempts == n_edges
        @warn(string("Did not find fault on ", edge))
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
