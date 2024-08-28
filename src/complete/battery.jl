module battery

using ..network_graph: Network, KeyType, labels, neighbor_labels
using ..network_graph: is_battery, get_battery_supply_power, get_load_power
using ..network_part: NetworkPart, Bus
using ...RelDist: Option

using DataStructures: PriorityQueue, dequeue_pair!

# Note that if there are parallel, equal power paths from the battery to a node, but one path is better
# than the other (either because of CENS or because it goes through nodes that connect to something better),
# we do not try both paths, thus we can't guarantee the best solution. I'm not really sure how to implement
# this without making a complicated mess, so I'm not prioritizing this very specific edge case.

#                 / load_a (2) --- load_b (2)  \
#                /                              \ 
#  battery(5) --<                                >-- load_c (1) --- feeder (1)
#                \                              / 
#                 \ load_d (2) --- load_e (2)  /
#                     |
#                   load_f (1)

# In the schema above it's better to take the lower path because it allows the feeder to supply load_f, 
# but this is not guaranteed

const RestPowerDict = Dict{KeyType,Float64}
const PrevNodeDict = Dict{KeyType,Option{KeyType}}

"""
A battery has a reach, which is a collection of the nodes it can supply. If we hit any of the loads in the reach of the battery, 
the battery must be removed from the list of batteries. The nodes leading to the battery must be given to the supply that consumed it.

`battery.reach["somekey"]` should contain the list of nodes on the shortest path. These should get added to the given part.

The search should have a list of batteries as constant data
it should also have a list of which batteries are and are taken as 


`supply 1 --- load 1 --- load 1 --- battery 1 --- load 1 --- load 1 --- battery 1``

In the example above, exactly two loads should be supplied.

"""
struct Battery
    battery_power::Float64
    prevs::PrevNodeDict
end


"""Find and initialize all batteries with their reach."""
function prepare_battery(network::Network)
    battery_labels = [node for node in labels(network) if is_battery(network, node)]
    batteries = Vector{Battery}()
    for battery in battery_labels
        # Find the rest_power for each node and the path taken to get there
        # Use a modified version of djikstra to create this
        graphdata = Dict((node => 0.0) for node in labels(network))
        start_power = get_battery_supply_power(network, battery)
        graphdata[battery] = start_power

        queue = PriorityQueue(Base.Order.Reverse, battery => start_power)
        # The seen nodes and the rest power we had last time we were there
        visited = RestPowerDict(battery => start_power)
        # Storing the prev node per node is enough to quickly backtrack to the battery later
        prev = PrevNodeDict(battery => nothing)

        while !isempty(queue)
            node, energy_left = dequeue_pair!(queue)
            for nbr in neighbor_labels(network, node)
                power_cost = get_load_power(network, nbr)
                if power_cost > energy_left
                    continue
                end
                prev_energy = get(visited, nbr, -Inf)
                new_energy = energy_left - power_cost
                if new_energy > prev_energy
                    visited[nbr] = new_energy
                    queue[nbr] = new_energy
                    prev[nbr] = node
                end
            end
        end

        push!(batteries, Battery(start_power, prev))
    end
    batteries, [false for _ in batteries]
end

"""Check if any active battery reach overlaps with any networkpart, and if they do immediately consume it.
This is NOT optional. If two parts both might consume a battery, which one does will be determined by iteration order,
and both will be visited."""
function visit_battery!(
    network::Network,
    batteries::Vector{Battery},
    visited_batteries::Vector{Bool},
    part::NetworkPart,
    node::KeyType,
)
    # 1. check if any part visited any battery
    # 2. give the nodes, mark battery as visited
    for (battery_idx, (battery, is_visited)) in enumerate(zip(batteries, visited_batteries))
        if is_visited
            continue
        end
        visited = Vector{KeyType}()
        _prev = get(battery.prevs, node, nothing)
        if _prev === nothing
            # Node is not in battery's reach
            continue
        end

        part.rest_power += battery.battery_power
        visited_batteries[battery_idx] = true
        visiting = node
        while visiting !== nothing
            if !(visiting in part.subtree)
                push!(visited, visiting)
                push!(part.subtree, visiting)
                push!(part.leaf_nodes, visiting)

                bus::Bus = network[visiting]
                part.rest_power -= get_load_power(bus)
            end
            visiting = battery.prevs[visiting]
        end

        # TODO: If this path visits another battery, visit that one too


        return visited, battery.battery_power, battery_idx
    end
    return nothing
end

function unvisit_battery!(
    network::Network,
    visited_batteries::Vector{Bool},
    part::NetworkPart,
    visited::Vector{KeyType},
    bonus_power::Float64,
    battery_idx::Int,
)
    # undo all the modifications made by visit_battery!()
    visited_batteries[battery_idx] = false
    part.rest_power -= bonus_power
    for node in visited
        pop!(part.subtree, node)
        pop!(part.leaf_nodes, node)

        bus::Bus = network[node]
        part.rest_power -= get_load_power(bus)
    end
end

end
