abstract type Source end

mutable struct Load <: Source
    P::Real
    nfc::Bool
end

"""
    Checks if there is a load in the graph at vertex v, and finds
    its power output and if it is nfc from the case.
"""
function get_load(g::MetaGraphs, case::Case, v::Int)
    # Check if there is load on the vertex
    if get_prop(g, v, :load)
        return Load(get_load_bus_power(network.case, get_prop(g, v, :name)),
                    get_prop(g, v, :nfc))
    else
        return Load(0.0, false)
    end
end
    

mutable struct Gen <: Source
    P::Real
    external::Bool
end

"""
    Checks if there is a generator in the graph at vertex v, and finds
    its power output and if it is external from the case.
"""
function get_gen(g::MetaGraphs, case::Case, v::Int)
    # Check if there is generation on the vertex
    if get_prop(g, v, :gen)
        return Gen(get_gen_bus_power(network.case, get_prop(g, v, :name)),
                   get_prop(g, v, :external))
    else
        return Gen(0.0, false)
    end
end
    

mutable struct Sources
    mapping::OrderedDict{Int, Real}
    tot::Real
end

function Sources()
    Sources(OrderedDict{Int, Real}(), 0.0)
end

"""
    Merges b into a.
"""
function merge!(a::Sources, b::Sources)
    merge!(a.mapping, b.mapping)
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
function update_part!(part::Part, gen::Gen, load::Load, v::Int)
    update_sources!(part.gens, gen, v)
    update_sources!(part.loads, load, v)
end

"""
    Merges one part into another part.
"""
function merge!(a::Part, b::Part)
    # The par gets the capacity of the part with the best capacity.
    a.capacity = a.capacity > b.capacity ? a.capacity : b.capacity

    # Merge the sources in the case.
    for prop in [:loads, :nfcs, :gens]
        merge!(getfield(a, prop), getfield(b, prop))
    end
end

"""
    Update the seen sources of a type of sources.
"""
function update_sources!(sources::Sources, source::Source, v::Int)
    sources.mapping[v] = source.P
    sources.tot += source.P
end

"""
    Returns the loading of a part

    This version is quite simple and merely uses the algebraic sum
    of consumption and production.
"""
function loading(Part::part)
    sum(getfield(sources).tot for sources in [:loads, :nfcs, :gens])
end


""" Calculate reachable vertices starting from a given edge"""
function calc_R(network::RadialPowerGraph,
                g::MetaGraph,
                e::Branch)::Array{Any}
    v = get_node_number(network.G, e.dst)
    vlist = traverse(g, v, e.rateA)
    return [get_bus_name(network.G, bus) for bus in vlist]
end

""" Calculate reachable vertices starting from a given edge"""
function calc_R(network::RadialPowerGraph,
                g::MetaGraph,
                b::Feeder)::Array{Any}
    v = get_node_number(network.G, b.bus)
    vlist = traverse(g, v, b.rateA)
    return [get_bus_name(network.G, bus) for bus in vlist]
end

function traverse(g::MetaGraph, start::Int = 0,
        feeder_cap::Real=Inf)::Vector{Int}
    @assert start in vertices(g) "can't access $start in $(props(g, 1))"
    
    parts = Dict{Int, Part}()
    reserves = Vector{Int}()
    floating = Vector{Int}()

    seen = Vector{Int}()
    visit = Vector{Int}([start])
    
    v_rec = 1 # The current vertex in the new graph being processed
    g_rec = SimpleGraph(v_rec) 

    part = Part(feeder_cap)
    parts[1] = part
    append!(reserves, 1)

    while !isempty(visit)
        next = pop!(visit)
        push!(seen, next)
        neighbors = setdiff(all_neighbors(g, next), seen)
        for n in neighbors
            e = Edge(next, n) in edges(g) ? Edge(next, n) : Edge(n, next)
            append!(visit, n)
        
            gen = get_gen(g, network.case, v)
            load = get_load(g, network.case, v)
            # Check if we have reached the capacity of the feeder connected to the part
            overloaded = loading(part) + load.P - gen.P - part.capacity > 0
            # Check if the edge is a switch
            is_switch = get_prop(g, e, :switch) > -1

            if overloaded 
                if is_switch
                    # We cannot add more load to the current part.
                    # Add a new vertex to the reconfiguation graph and 
                    # create a new part.
                    add_vertex!(g_rec)

                    # This only works if we don't have an intersection
                    add_edge!(g_rec, v_rec, v_rec+1)
                    v_rec += 1
                    part = Part()
                    # Mark the node in the reconfiguration graph as floating
                    append!(floatin, v_rec)
                end
            else 
                if is_switch
                    # We found a switch update the previous part with 
                    # what we have found so far.
                    merge(parts[v_rec], part) # Check if work with intersections

                   # Create a new part
                    part = Part()
                    # I guess we can add stuff to it later in the code
                end
            end
            # Here we can add stuff to the currently active part.
            update_part!(part, gen, load)
        end
    end
    reachable = Vector{Int}()
    for reserve in reserves
        append!(reachable, keys(part.load))
    end

    return reachable
end
