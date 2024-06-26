using Graphs
using SintPowerGraphs
using MetaGraphs
import Base.==
import Base.<

struct Branch{T} <:AbstractEdge{T}
    src::T
    dst::T
    rateA::Real
end

"""
    Check if a reserve is in a set of vertices.
"""
function reserve_in_vertices(g::MetaGraph, b::Branch, v::Vector{Int})
    g[b.src, :name] ∈ v || g[b.dst, :name]
end


function Branch(t::Tuple)
    Branch(t[1], t[2], rateA)
end

function reverse(edge::Branch)
    return Branch(edge.dst, edge.src, edge.rateA)
end

(==)(e1::Branch, e2::Branch) = (e1.src == e2.src && e1.dst == e2.dst)

struct Feeder
    bus::String
    rateA::Real
end

"""
    Check if a reserve is in a set of vertices.
"""
function reserve_in_vertices(g::MetaGraph, f::Feeder, v::Vector{Int})
    g[f.bus, :name] ∈ v
end

"""
    Returns the buses that can supply loads.
"""
function get_slack(network::RadialPowerGraph, consider_cap::Bool)::Array{Any}
    transformers = network.mpc.transformer
    F = []
    for e in eachrow(transformers)
        push!(F, Branch(e.f_bus, e.t_bus, consider_cap ? e.rateA : Inf))
    end
    if isempty(F)
        for row in eachrow(network.mpc.gen)
            if row.external
                push!(F, Feeder(row.bus, consider_cap ? row.Pmax : Inf))
            end
        end
        if isempty(F)
            F = [Feeder(network.ref_bus,
                        consider_cap ? get_feeder_cap(network, network.ref_bus) : Inf)]
        end
    end
    return F
end

"""
    Check if a node is a reserve.
"""
function is_reserve(f::Feeder, bus::String)
    f.bus == bus
end

function is_reserve(b::Branch, bus::String)
    b.dst == bus || b.src == bus
end


"""
    Check if a transformer that can be used to supply the network is
    connected to the reference bus. The reference bus is the bus
    that supplies the network through a normally closed switch.
"""
function slack_is_ref_bus(network::RadialPowerGraph, b::Branch)
   ref = network.mpc.bus[network.mpc.ref_bus, :ID]
    b.src == ref || b.dst == ref
end

function slack_is_ref_bus(network::RadialPowerGraph, f::Feeder)
    any(network.mpc.bus[network.mpc.ref_bus, :ID].==f.bus)
end

function create_slack_name(b::Branch)
    b.src*"-"*b.dst
end

function create_slack_name(f::Feeder)
    f.bus
end

""""
    Returns the capacity of a feeder.
"""
function get_feeder_cap(network::RadialPowerGraph, feeder::String)::Real
    network.mpc.gen[network.mpc.gen.bus.==feeder, :Pmax][1]
end

function are_edges_equal(e_input, e_test)::Bool
    return e_input == e_test || e_input == reverse(e_test)
end

function edge2branch(g::AbstractMetaGraph, e::Graphs.SimpleGraphs.SimpleEdge{Int64})::Branch
    s = get_bus_name(g, src(e))
    d = get_bus_name(g, dst(e))
    return Branch(s,d, get_prop(g, src(e), dst(e), :rateA))
end

struct Switch 
    src::String
    dst::String
    t_manual::Real
    t_remote::Real
end

"""
    Constructs an empty switch.
"""
function Switch()
    Switch("NA", "NA", 0, 0)
end

"""
    Overloading of comparison operator for switches. If both switches have an equal remote swithcing
    time it compares the manual switching time, otherwise it compares the remote switching time.
"""
(<)(s1::Switch, s2::Switch) = (s1.t_remote==s2.t_remote ? s1.t_manual<s2.t_manual : s1.t_remote<s2.t_remote)

function get_minimum_switching_time(s::Switch)
    return s.t_remote < s.t_manual ? s.t_remote : s.t_manual
end
