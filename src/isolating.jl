module isolating

using ..network_graph: Network, KeyType, ne, is_supply, is_main_supply, neighbor_labels
using ..network_graph: label_for, labels, NewSwitch, find_main_supply
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
    visit = [start]
    while !isempty(visit)
        v = pop!(visit)
        push!(seen, v)
        for v_dst in setdiff(neighbor_labels(network, v), seen)
            push!(visit, v_dst)
        end
    end
    # Don't keep ignore in what has been seen
    return seen[2:end]
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
  This function reduces the search area based on an indicator or switch located attempts
  vertex v. It also deletes the part of the graph where the fault is not and updates the
  location of the feeder. It also calculates the number of vertices left that can being
  seen from the current feeder.
    
  Args:
    network: The graph we are investigating.
    edge: The faulted edge.
    v: Vertex with indicator or switch.
    nbr: The vertex on the same edge as v.
    feeder: The vertex used as feeder
"""
function reduce_search_area!(
    network::Network,
    edge::Tuple{KeyType,KeyType},
    v::KeyType,
    nbr::KeyType,
    feeder::KeyType,
)
    v_sees = dfs(network, v, [nbr])
    nbr_sees = dfs(network, nbr, [v])

    # Find the direction of the feeder
    feeder_dir = feeder ∈ v_sees ? v : nbr

    if sort((v, nbr)) == sort(edge) || issubset(edge, nbr_sees)
        # If the fault is on the edge or the same side as the neighbor we delete the branches going
        # out from v. 
        for v_dst in neighbor_labels(network, v)
            if v_dst != nbr
                delete!(network, v, v_dst)
            end
        end
        if feeder_dir == v
            # The feeder is in the same direcition as v, we move the feeder to v.
            feeder = v
            nv = length(nbr_sees) + 1 # Keep v in nv length
        else
            nv = length(v_sees) + 1 # Keep 
        end
    else
        # If the fault is on the same side as v we just delete the edge (v, nbr)
        delete!(network, v, nbr)
        if feeder_dir == v
            # If v is in the direction of the feeder we keep the old feeder
            nv = length(v_sees) # Calculate new lenght of graph without nbr
        else
            # We have to update what we use as the feeder
            feeder = v
            nv = length(nbr_sees) # New length of graph without v
        end
    end
    return feeder, nv
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
    nv = Inf
    tₛ = 0
    attempts = 0
    n_edges = ne(network)
    let network = deepcopy(network)
        indicator_edges = find_fault_indicators(network, edge[1])
        # We know that the fault will be between the indicators so we remove the
        # indicators from the graph
        for indicator_edge in unique(indicator_edges)
            # The search find_fault_indicators finds too much.
            if sort(indicator_edge) ∉ sort.(edge_labels(network))
                continue
            end
            indicators = network[indicator_edge...].indicators
            if Set(indicators) == Set(edge)
                # There are indicators on both sides of the edge where the fault is
                # we are done
                tₛ += findmin([s.switching_time for s in network[edge...].switches])[1]

                return (tₛ + t_f, attempts)
            end
            if length(indicators) > 1
                # The edge has more than one indicator. Find the one closest to the
                # fault.
                for i_bus in indicators
                    nbr = indicator_edge[1] == i_bus ? indicator_edge[2] : indicator_edge[1]
                    found, nv = find_vertices(network, collect(edge), i_bus, [nbr])
                    if found
                        break
                        feeder, nv = reduce_search_area!(network, edge, i_bus, nbr, feeder)
                    end
                end
            else
                i_bus = indicators[1]
                nbr = indicator_edge[1] == i_bus ? indicator_edge[2] : indicator_edge[1]
                feeder, nv = reduce_search_area!(network, edge, i_bus, nbr, feeder)
            end
        end

        switch = deepcopy(edge)
        while nv > 2 && attempts < n_edges
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
                switches = vcat([(src, dst) for dst in nbr if dst != src])
                nbrs = vcat(nbrs, nbr)
            end

            if length(unique(nbrs)) < 2
                return (tₛ, attempts - 1)
            end

            # Now we have to choose the switch to operate.
            s_times = Vector{Real}()
            s_buses = Vector{String}()
            nbr_buses = Vector{KeyType}()
            brn_frm_fdr = sum(feeder .∈ switches)
            for temp_s in switches
                temp_switches = network[temp_s...].switches
                if brn_frm_fdr > 1
                    # More than one branch from the feeder bus. Allow switching at feeder.
                    tmp_times = [s.switching_time for s in temp_switches]
                else
                    # Only one branch from feeder, we don't attempt the feeder.
                    tmp_times = [s.switching_time for s in temp_switches if s.bus != feeder]
                end
                if !isempty(tmp_times)
                    temp_time, j = findmin(tmp_times)
                    push!(s_times, temp_time)
                    push!(s_buses, temp_switches[j].bus)
                    push!(
                        nbr_buses,
                        temp_switches[j].bus == temp_s[1] ? temp_s[2] : temp_s[1],
                    )
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
                nbr_bus = nbr_buses[min_times[1]]
            else
                # More than one switch was the fastest. We choose the one closest
                # to the feeder.
                found = false
                seen_length = -1
                l_i = 0
                for (i, tmp_bus) in enumerate(s_buses)
                    if tmp_bus != ""
                        found, seen = find_vertices(
                            network,
                            [feeder],
                            tmp_bus,
                            convert.(KeyType, setdiff(nbrs, tmp_bus)),
                        )
                        tmp_l = length(seen)
                        if seen_length < tmp_l
                            seen_length = tmp_l
                            l_i = i
                        end
                        if found
                            switch = switches[min_times[i]]
                            tₛ += s_times[min_times[i]]
                            s_bus = s_buses[min_times[i]]
                            nbr_bus = nbr_buses[min_times[i]]
                            break
                        end
                    end
                end
                # Check if one of the fastest switches were closest to the feeder
                if !found
                    # None of the fastest switches were closest to the feeder.
                    # Choose the one that saw the most
                    switch = switches[l_i]
                    s_bus = s_buses[l_i]
                    nbr_bus = nbr_buses[l_i]
                end
            end

            feeder, nv = reduce_search_area!(network, edge, s_bus, nbr_bus, feeder)
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
