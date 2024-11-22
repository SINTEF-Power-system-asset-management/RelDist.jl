module network_graph

using Graphs: SimpleGraph, Graph
import Graphs: connected_components, center
using MetaGraphsNext: MetaGraphsNext
import MetaGraphsNext: labels, edge_labels, neighbor_labels, nv, ne, label_for
import MetaGraphsNext: haskey, setindex!, getindex, delete!
using SintPowerCase: Case
using DataFrames: outerjoin, keys
using DataStructures: DefaultDict, Queue

import Base

using ...RelDist: PieceWiseCost, calculate_kile

### Bus
@enum BusKind t_supply t_battery t_load t_nfc_load
mutable struct SupplyUnit
    id::String
    power::Float64 # This is the rating. We can consider to rename it.
    is_battery::Bool
    energy::Real
end

mutable struct LoadUnit
    id::String
    power::Float64
    type::String # e.g. residental/industry
    correction_factor::Real
    is_nfc::Bool
    in_service::Bool
end
struct Bus
    loads::Vector{LoadUnit}
    supplies::Vector{SupplyUnit}
end


"""Simple constructor to be compatible with previous versions of tests"""
function Bus(id::String, type::BusKind, power::Float64)
    if type == t_supply
        Bus([], [SupplyUnit(id, power, false, Inf)])
    elseif type == t_battery
        Bus([], [SupplyUnit(id, power, true, 0)])
    elseif type == t_load
        Bus([LoadUnit(id, power, "residental", 1.0, false, true)], [])
    elseif type == t_nfc_load
        Bus([LoadUnit(id, power, "residental", 1.0, true, true)], [])
    end
end

"""JUST A HELPER FOR THE FOLLOWING FUNCTIONS, DO NOT EXPORT"""
function get_supply_power_and_is_battery(bus::Bus)
    # If a battery and a feeder is on the same bus, we can treat the bus as a feeder
    summy = 0.0
    is_battery = true
    for supply in bus.supplies
        if !supply.is_battery
            is_battery = false
        end
        summy += supply.power
    end
    # If there are loads on the same bus then we must supply them
    for load::LoadUnit in bus.loads
        if !load.is_nfc
            summy -= load.power
        end
    end
    # If the loads are bigger than the supply then we should treat it as a load
    # not a negative power supply.
    max(summy, 0.0), is_battery
end

function get_supply_power(bus::Bus)
    power, is_battery = get_supply_power_and_is_battery(bus)
    !is_battery ? power : 0.0
end

is_supply(bus::Bus) = get_supply_power(bus) > 0.0

function get_battery_supply_power(bus::Bus)
    power, is_battery = get_supply_power_and_is_battery(bus)
    is_battery ? power : 0.0
end

is_battery(bus::Bus) = get_battery_supply_power(bus) > 0.0

function get_load_power(bus::Bus; consider_supply = true)
    summy = 0.0
    for load::LoadUnit in bus.loads
        if load.is_nfc || !load.in_service
            continue
        end
        summy += load.power
    end
    if consider_supply
        for supply::SupplyUnit in bus.supplies
            summy -= supply.power
        end
    end
    max(summy, 0.0)
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

"""
    sheds a load.
"""
function shed_load!(load::LoadUnit)
    load.in_service = false
end

"""
    Sheds all load on a bus.
"""
function shed_load!(bus::Bus)
    for load in bus.loads
        shed_load!(load)
    end
end

function get_kile(
    load::LoadUnit,
    outage_time::Float64,
    cost_functions::AbstractDict{String,PieceWiseCost},
    correction_factor::Float64 = 1.0,
)
    if load.is_nfc
        return 0.0
    end
    calculate_kile(load.power, outage_time, cost_functions[load.type], correction_factor)
end

is_nfc(bus::Bus) = get_nfc_load_power(bus) > 0.0
is_load(bus::Bus) = get_load_power(bus) > 0.0

### /Bus
### Branch

const KeyType = String

struct NewSwitch
    bus::KeyType
    is_closed::Bool
    is_breaker::Bool
    switching_time::Float64

    NewSwitch(
        bus::String = "you should have a key here if you're not testing code",
        is_closed::Bool = false,
        is_breaker::Bool = false,
        switching_time::Float64 = 0.2,
    ) = new(bus, is_closed, is_breaker, switching_time)
end

function time_to_cut(switch::NewSwitch)
    if !switch.is_closed
        0.0
    else
        switch.switching_time
    end
end

mutable struct NewBranch
    repair_time::Float64 # h
    permanent_fault_frequency::Float64
    switches::Vector{NewSwitch}
    indicators::Vector{KeyType}
end

"""Creates a branch with a single switch"""
NewBranch(bus = "you should have a key here too if you're not testing code") =
    NewBranch(0.512, 0.123, [NewSwitch(bus)], Vector{KeyType}())
NewBranch()

function is_switch(branch::NewBranch)
    length(branch.switches) > 0
end

get_min_cutting_time(branch::NewBranch) = minimum(s -> time_to_cut(s), branch.switches)

const VertexType = Bus
const EdgeType = NewBranch

struct Network
    network::MetaGraphsNext.MetaGraph{Int,SimpleGraph{Int},KeyType,VertexType,EdgeType}
    switching_time::Float64
    repair_time::Float64
end

# network[label] = vertex
# network[labe, label] = edge

"""Create a Network. If this is a subgraph after a fault switching time and repair time
are the times it takes to respectively reorganize and fix the fault on the network.
If not then they don't mean anything."""
function Network(switching_time = 0.5, repair_time = 4.0)
    network = MetaGraphsNext.MetaGraph(
        Graph();
        label_type = KeyType,
        vertex_data_type = VertexType,
        edge_data_type = EdgeType,
    )
    Network(network, switching_time, repair_time)
end

empty_network() = Network()
# Forwarding methods to the inner network
labels(network::Network) = labels(network.network)
label_for(network::Network, v::Integer) = label_for(network.network, v)
edge_labels(network::Network) = edge_labels(network.network)
neighbor_labels(network::Network, key::KeyType) = neighbor_labels(network.network, key)
haskey(network::Network, key::KeyType) = haskey(network.network, key)
haskey(network::Network, key_a::KeyType, key_b::KeyType) =
    haskey(network.network, key_a, key_b)
setindex!(network::Network, value::VertexType, key::KeyType) =
    setindex!(network.network, value, key)
getindex(network::Network, key::KeyType) = getindex(network.network, key)
setindex!(network::Network, value::EdgeType, key_a::KeyType, key_b::KeyType) =
    setindex!(network.network, value, key_a, key_b)
getindex(network::Network, key_a::KeyType, key_b::KeyType) =
    getindex(network.network, key_a, key_b)
delete!(network::Network, key::KeyType) = delete!(network.network, key)
delete!(network::Network, key_a::KeyType, key_b::KeyType) =
    delete!(network.network, key_a, key_b)
nv(network::Network) = nv(network.network)
ne(network::Network) = ne(network.network)

# Forwarding methods to the bus
get_supply_power(network::Network, node::KeyType) = get_supply_power(network[node])
is_supply(network::Network, node::KeyType) = is_supply(network[node])
get_battery_supply_power(network::Network, node::KeyType) =
    get_battery_supply_power(network[node])
is_battery(network::Network, node::KeyType) = is_battery(network[node])
get_load_power(network::Network, node::KeyType) = get_load_power(network[node])
get_nfc_load_power(network::Network, node::KeyType) = get_nfc_load_power(network[node])
is_nfc(network::Network, node::KeyType) = is_nfc(network[node])
is_load(network::Network, node::KeyType) = is_load(network[node])

# Convenience iterators
branches(network) = map(edge -> network[edge...], edge_labels(network))
buses(network) = map(node -> network[node], labels(network))

"""
    Returns the labels of the vertices in the conneceted components.
"""
function connected_components(network::Network)
    labels = Vector{Vector{KeyType}}()
    for subnet_indices in connected_components(network.network)
        push!(labels, [label_for(network.network, idx) for idx in subnet_indices])
    end
    return labels
end

"""Create Network instances for each of the connected_components in the network.
Pass in the switching and repair times for convenience."""
function connected_components(
    network::Network,
    switching_time,
    repair_time,
)::Vector{Network}
    comps = []
    for subnet_indices in connected_components(network.network)
        subnet = Network(switching_time, repair_time)
        subnet_labels = [label_for(network.network, idx) for idx in subnet_indices]
        [
            subnet[label] = network[label] for
            label in labels(network) if label in subnet_labels
        ]
        [
            subnet[edge...] = network[edge...] for edge in edge_labels(network) if
            edge[1] in subnet_labels && edge[2] in subnet_labels
        ]
        push!(comps, subnet)
    end
    comps
end

"""
Function that check if a supply is the main supply of the network. It assumes that only
the main supply of the supplies have a closed switch.
"""
function is_main_supply(network::Network, supply::KeyType)
    for neighbor in neighbor_labels(network, supply)
        for switch in network[supply, neighbor].switches
            if !switch.is_closed
                return false
            end
        end
    end
    return true
end

"""
Function that finds the main supply of the network. It assumes that only the main supply
of the supplies have a closed switch.
"""
function find_main_supply(network::Network)
    for supply in [vertex for vertex in labels(network) if is_supply(network[vertex])]
        if is_main_supply(network, supply)
            return supply
        end
    end
end

"""
    Returns the circuit breaker of a supply.
"""
function find_supply_breaker(network::Network, supply::KeyType)
    for nbr in neighbor_labels(network, supply)
        for switch in network[supply, nbr].switches
            if switch.is_breaker
                return switch
            end
        end
    end
end

function find_supply_breaker_time(network::Network, supply::KeyType)
    supply = find_supply_breaker(network, supply)
    return isnothing(supply) ? Inf : supply.switching_time
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

end # module network
