using OrderedCollections
using DataStructures

abstract type Source end

mutable struct Loadr <: Source
    bus::String
    P::Real
    nfc::Bool
    shed::Bool
end

"""
    Checks if there is a load in the graph at vertex v, and finds
    its power output and if it is nfc from the mpc.
"""
function get_load(g::MetaGraph, mpc::Case, v::Int)
    # Check if there is load on the vertex
    if get_prop(g, v, :load)
        return Loadr(get_prop(g, v, :name),
                     get_load_bus_power(mpc, get_prop(g, v, :name)),
                     get_prop(g, v, :nfc), false)
    else
        return Loadr(get_prop(g, v, :name), 0.0, false, false)
    end
end
    
mutable struct Gen <: Source
    bus::String
    P::Real
    external::Bool
end

"""
    Checks if there is a generator in the graph at vertex v, and finds
    its power output and if it is external from the mpc.
"""
function get_gen(g::MetaGraph, mpc::Case, v::Int)
    # Check if there is generation on the vertex
    if get_prop(g, v, :gen)
        return Gen(get_prop(g, v, :name),
                   get_gen_bus_power(mpc, get_prop(g, v, :name)),
                   get_prop(g, v, :external))
    else
        return Gen(get_prop(g, v, :name), 0.0, false)
    end
end

mutable struct Sources{T}
    sources::Stack{T}
    buses::Stack{String}
    shed::Stack{String}
    P::Real
    P_shed::Real
end

function Sources{T}() where T
    Sources(Stack{T}(), Stack{String}(), Stack{String}(), 0, 0)
end
    
mutable struct Part
    capacity::Real

    loads::Sources{Loadr}
    
    gens::Sources{Gen}

    vertices::Vector{Int}
end

function Part()
    Part(Inf, Sources{Loadr}(), Sources{Gen}(), Vector{Int}())
end

function Part(capacity::Real)
    Part(capacity, Sources{Loadr}(), Sources{Gen}(), Vector{Int}())
end

function Part(capacity::Real, v_start::Integer)
    Part(capacity, Sources{Loadr}(), Sources{Gen}(), [v_start])
end

"""
    Updates a part.
    Args:
        part: The part to update
        gen: A Gen struct with information regarding generators
        to be added.
        load: A Load struct with information regarding loads
        to be added.
        v: The vertex of the original graph that we are processing.
"""
function update_part!(part::Part, gen::Gen, load::Loadr, v::Integer)
    update_sources!(part.loads, load)
    update_sources!(part.gens, gen)
    append!(part.vertices, v)
end

function update_sources!(sources::Sources, source::Source)
    push!(sources.sources, source)
    push!(sources.buses, source.bus)
    sources.P += source.P
end

""""
    Shed load in sources.
"""
function shed_load!(sources::Sources, load::Loadr)
    sources.P -= load.P
    sources.P_shed += load.P
    push!(sources.sources, load)
    push!(sources.shed, load.bus)
end

"""
    Returns the names of the loads that are in service.
"""
function in_service_loads(part::Part)
    in_service_sources(part.loads)
end

function in_service_sources(sources::Sources)
    setdiff(sources.buses, sources.shed)
end

"""
    Returns the loading of a part

    This version is quite simple and merely uses the algebraic sum
    of consumption and production.
"""
function loading(part::Part)
    part.loads.P-part.gens.P
end

""" Calculate reachable vertices starting from a given edge"""
function calc_R(network::RadialPowerGraph,
                g::MetaGraph,
                e::Branch)::Part
    v = get_node_number(network.G, e.dst)
    traverse(network, g, v, e.rateA)
end

""" Calculate reachable vertices starting from a given edge"""
function calc_R(network::RadialPowerGraph,
                g::MetaGraph,
                b::Feeder)::Part
    v = get_node_number(network.G, b.bus)
    traverse(network, g, v, b.rateA)
end

function traverse(network::RadialPowerGraph, g::MetaGraph, start::Int = 0,
        feeder_cap::Real=Inf)
    @assert start in vertices(g) "can't access $start in $(props(g, 1))"
    
    parents = Dict{Int, Int}()

    seen = Vector{Int}()
    visit = Vector{Int}([start])
    
    part = Part(feeder_cap, start)

    while !isempty(visit)
        v_src = pop!(visit)
        if !(v_src in seen)
            push!(seen, v_src)
            for v_dst in setdiff(all_neighbors(g, v_src), seen)
                e = Edge(v_src, v_dst)
               
                load = get_load(g, network.mpc, v_dst)
                gen = get_gen(g, network.mpc, v_dst)

                # Check if we have reached the capacity of the feeder connected to the part
                overload = loading(part) + load.P - gen.P - part.capacity
                update_part!(part, gen, load, v_dst)

                if overload > 0
                    for nfc in part.loads.sources # can probably overload something to make this cleaner
                        # If we have not already shed the load
                        if !nfc.shed
                            shed_load!(part.loads, nfc)
                            if overload - nfc.P < 0
                                # We removed the overload stop shedding
                                break
                            end
                        end
                    end
                end
                
                # Check if we managed to solve the load by load shedding
                overload = loading(part) + load.P - gen.P - part.capacity
                if overload > 0
                    # We did not solve the overload, mark it as shed
                    shed_load!(part.loads, load)
                end

                if overload < 0 || (get_prop(g, e, :switch) == -1)
                    # We have to keep exploring the graph until we find a switch
                    # or until we get overloaded
                    append!(visit, v_dst)
                end
            end
        end
    end
    return part
end

