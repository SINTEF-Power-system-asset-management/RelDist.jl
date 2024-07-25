module network_graph

using Graphs: SimpleGraph, Graph
import Graphs: connected_components
using MetaGraphsNext: MetaGraphsNext, label_for
import MetaGraphsNext: labels, edge_labels, neighbor_labels
import MetaGraphsNext: haskey, setindex!, getindex, delete!
using SintPowerCase: Case
using DataFrames: outerjoin, keys
using DataStructures: DefaultDict, Queue

import Base

using ...RelDist: PieceWiseCost, calculate_kile

### Bus
@enum BusKind t_supply t_load t_nfc_load
struct SupplyUnit
    id::String
    power::Float64
end

struct LoadUnit
    id::String
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
function Bus(id::String, type::BusKind, power::Float64)
    if type == t_supply
        Bus([], [SupplyUnit(id, power)])
    elseif type == t_load
        Bus([LoadUnit(id, power, "residental", 1.0, false)], [])
    elseif type == t_nfc_load
        Bus([LoadUnit(id, power, "residental", 1.0, true)], [])
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

function get_kile(
    load::LoadUnit,
    outage_time::Float64,
    cost_functions::AbstractDict{String,PieceWiseCost},
    correction_factor::Float64=1.0,
)
    if load.is_nfc
        return 0.0
    end
    calculate_kile(load.power, outage_time, cost_functions[load.type], correction_factor)
end

# only for visualization
is_nfc(bus::Bus) = get_nfc_load_power(bus) > 0.0

function is_supply(bus::Bus)
    length(bus.supplies) !== 0
end

function is_load(bus::Bus)
    length(bus.loads) !== 0
end

### /Bus
### Branch

const KeyType = String

struct NewSwitch
    bus::KeyType
    is_closed::Bool
    switching_time::Float64
end

NewSwitch() = NewSwitch("you should have a key here if you're not testing code", false, 0.2)

function time_to_cut(switch::NewSwitch)
    if !switch.is_closed
        0.0
    else
        switch.switching_time
    end
end

struct NewBranch
    repair_time::Float64 # h
    permanent_fault_frequency::Float64
    switches::Vector{NewSwitch}
end

NewBranch() = NewBranch(0.512, 0.123, [NewSwitch()])

function is_switch(branch::NewBranch)
    length(branch.switches) > 0
end

get_min_cutting_time(branch::NewBranch) = minimum(s -> time_to_cut(s), branch.switches)

const VertexType = Bus
const EdgeType = NewBranch

mutable struct Network
    network::MetaGraphsNext.MetaGraph{Int,SimpleGraph{Int},KeyType,VertexType,EdgeType}
    switching_time::Float64
    repair_time::Float64
end

# network[label] = vertex
# network[labe, label] = edge

"""Create a Network. If this is a subgraph after a fault switching time and repair time
are the times it takes to respectively reorganize and fix the fault on the network.
If not then they don't mean anything."""
function Network(switching_time=0.5, repair_time=4.0)
    network = MetaGraphsNext.MetaGraph(
        Graph();
        label_type=KeyType,
        vertex_data_type=VertexType,
        edge_data_type=EdgeType,
    )
    Network(network, switching_time, repair_time)
end

empty_network() = Network()
# Forwarding methods to the inner network
labels(network::Network) = labels(network.network)
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

"""Create Network instances for each of the connected_components in the network.
Pass in the switching and repair times for convenience."""
function connected_components(
    network::Network,
    switching_time=0.592,
    repair_time=4.0,
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