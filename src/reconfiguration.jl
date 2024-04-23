using OrderedCollections

abstract type Source end

mutable struct Loadr <: Source
    bus::String
    P::Real
    nfc::Bool
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
                     get_prop(g, v, :nfc))
    else
        return Loadr(get_prop(g, v, :name), 0.0, false)
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
    

mutable struct Sources
    mapping::OrderedDict{String, Real}
    tot::Real
end

function Sources()
    Sources(OrderedDict{Int, Real}(), 0.0)
end

function get_names(sources::Sources)
    keys(sources.mapping)
end

"""
    Merges b into a.
"""
function merge!(a::Sources, b::Sources)
    Base.merge!(a.mapping, b.mapping)
    a.tot += b.tot
end

mutable struct Part
    capacity::Real

    loads::Sources
    nfcs::Sources
    gens::Sources
end

function Part()
    Part(Inf, Sources(), Sources(), Sources())
end

function Part(capacity::Real)
    Part(capacity, Sources(), Sources(), Sources())
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
function update_part!(part::Part, gen::Gen, load::Loadr)
    update_sources!(part.gens, gen)
    update_sources!(part.loads, load)
end

function get_loads(part::Part)
    get_names(part.loads)
end

"""
    Merges one part into another part.
"""
function merge!(a::Part, b::Part)
    # The part gets the capacity of the part with the worst capacity.
    a.capacity = a.capacity < b.capacity ? a.capacity : b.capacity

    # Merge the sources in the mpc.
    for prop in [:loads, :nfcs, :gens]
        merge!(getfield(a, prop), getfield(b, prop))
    end
end

"""
    Update the seen sources of a type of sources.
"""
function update_sources!(sources::Sources, source::Source)
    sources.mapping[source.bus] = source.P
    sources.tot += source.P
end

"""
    Returns the loading of a part

    This version is quite simple and merely uses the algebraic sum
    of consumption and production.
"""
function loading(part::Part)
    sum(getfield(part, sources).tot for sources in [:loads, :nfcs, :gens])
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
    
    part = Part(feeder_cap)

    while !isempty(visit)
        v_src = pop!(visit)
        if !(v_src in seen)
            push!(seen, v_src)
            for v_dst in setdiff(all_neighbors(g, v_src), seen)
                e = Edge(v_src, v_dst)
            
                gen = get_gen(g, network.mpc, v_dst)
                load = get_load(g, network.mpc, v_dst)
                # Check if we have reached the capacity of the feeder connected to the part
                overloaded = loading(part) + load.P - gen.P - part.capacity > 0

                if overloaded
                    if get_prop(g, e, :switch) == -1
                        # We have to keep exploring the graph until we find a switch
                        append!(visit, v_dst)
                       
                        # We don't have a switch here, so I just keep it in the graph
                        update_part!(part, gen, load)
                    end
                    # We are overloaded and the branch is a swithc so we stop exploring
                    # graph.
                else
                    # If we are not overloaded we update the current part
                    update_part!(part, gen, load)
                    # Keep on exploring the graph
                    append!(visit, v_dst)
                end
            end
        end
    end
    return part
end

