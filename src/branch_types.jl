using Graphs
import Base.==
import Base.<

struct Branch{T} <:AbstractEdge{T}
    src::T
    dst::T
    rateA::Real
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
