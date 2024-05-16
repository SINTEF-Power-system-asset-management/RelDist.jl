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

    vertices::Set{Int}

    switches::Vector{Switch}
end

function Part()
    Part(Inf, Sources{Loadr}(), Sources{Gen}(), Set{Int}(), Vector{Switch}())
end

function Part(capacity::Real)
    Part(capacity, Sources{Loadr}(), Sources{Gen}(), Set{Int}(), Vector{Switch}())
end

function Part(capacity::Real, v_start::Integer)
    Part(capacity, Sources{Loadr}(), Sources{Gen}(), Set([v_start]), Vector{Switch}())
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
    push!(part.vertices, v)
end

"""
    Return the vertices in the parts that intersect.
"""
function Base.intersect(part_a::Part, part_b::Part)
    intersect(part_a.vertices, part_b.vertices)
end

"""
    Check if a part is a subset of another
"""
function Base.:⊆(part_a::Part, part_b::Part)
    ⊆(part_a.vertices, part_b.vertices)
end

"""
    Check if a reserve is in an island.
"""
function reserve_in_island(part::Part, island::Vector{Int})
    # The reserve is the first vertex
    part.vertices[1] ∈ island
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

"""
    Returns true if any load has been shed.
"""
function any_shed(part::Part)
    return part.loads.P_shed > 0
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
                    for load in part.loads.sources # can probably overload something to make this cleaner
                        # Shed nfc that has not been sked
                        if load.nfc && !nfc.shed
                            shed_load!(part.loads, nfc)
                            if overload - load.P < 0
                                # We removed the overload stop shedding
                                break
                            end
                        end
                    end
                    # Check if we managed to solve the overload by shedding ncf
                    overload = loading(part) + load.P - gen.P - part.capacity
                
                    if overload > 0
                        # We did not solve the overload, mark it as shed
                        shed_load!(part.loads, load)
                        if get_prop(network.G, e, :switch) == 1
                            push!(part.switches, get_switch(network, e))
                        end
                    end
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

mutable struct Overlapping
    g::MetaGraph
    parts::Vector{Part}
    part::Part
    old_p::Part
    old_i::Int
    overlapping::Set{Int}
    add_new_part::Bool
end

function Overlapping(g::MetaGraph, parts::Vector{Part}, part::Part)
    Overlapping(g, parts, part, Part(), 0, Set{Int}(), true)
end

function update_overlapping!(o::Overlapping, old_p::Part,
        old_i::Int, overlapping::Set{Int})
    o.old_p = old_p
    o.old_i = old_i
    o.overlapping = overlapping
end

function vertices_equal(o::Overlapping)
    o.old_p.vertices == o.part.vertices
end

function part_is_subset(o::Overlapping)
    o.part ⊆ o.old_p
end

function old_part_is_subset(o::Overlapping)
    o.old_p ⊆ o.part
end

function delete_old_part!(o::Overlapping)
    deleteat!(o.parts, o.old_i)
end

function new_part_has_better_cap(o::Overlapping)
    o.old_p.capacity < o.part.capacity
end

function islands_in_parts(o::Overlapping, i_1::Vector{Array}, i_2::Vector{Array})
    reserve_in_island(o.part, i_1) && reserve_in_island(o.old_part, i_2)
end

function parts_split(o::Overlapping, islands::Vector{Vector{Int}})
    (islands_in_parts(o, islands[1], islands[2]) ||
     islands_in_parts(o, islands[2], islands[1]))
 end

function check_overlap_and_fix!(g::MetaGraph,
        parts::Vector{Part}, part::Part)
    o = Overlapping(g, parts, part)
    for (old_i, old_p) in enumerate(parts)
        overlapping = intersect(old_p, part)
        if length(overlapping) > 0
            # old_p is overlapping with part. We have to fix it
            update_overlapping!(o, old_p, old_i, overlapping)
            fix_overlap!(o)
            # Check if part is a subset of a previous part.
            if !o.add_new_part
                return
            end
        end
    end
    push!(parts, part)
end

function fix_overlap!(o::Overlapping)
    # First we check if there is a complete overlap.
    # Or if one part is a subset of the other.
    # In these cases we just disregard one of the parts. Although,
    # in cases with renewables a reconfiguration may be more
    # optimal.
    if vertices_equal(o)
        return fix_parts_with_same_vertices!(o) 
        # Here we check if one part is a subset of the other
        # I am not sure how realistic this is, but nice to
        # be certain.
    elseif old_part_is_subset(o)
        # The old part is a subset of part. We kick
        # out the old part. 
        delete_old_part!(o)
    elseif part_is_subset(o)
        # The part is a subset of the old part. We don't add the new part
        # Since we kick out the new part we can continue, we should return false
        # so we know to not add the new part.
        o.add_new_part = false
    else
        # old_p an part are not subsets of each other. This means
        # that we need to determine whether it is possible to
        # split them.
        find_reconfiguration_switches!(o)
    end
end

function fix_parts_with_same_vertices!(o::Overlapping)
   # The reserves cover the same vertices. We keep the one
   # that has the largest capacity.
   if new_part_has_better_cap(o)
       # The new part has a better capacity.
       # Kick out the old one
       delete_old_part!(o)
    else
        o.add_new_part = false
    end
end

function find_reconfiguration_switches!(o::Overlapping)
    common_switches = Vector{Edge}()
    for common in o.overlapping
        for n in all_neighbors(o.g, common)
            if (n ∉ o.part.vertices || n ∉ o.old_p.vertices)
                # This is a line going between the parts
                if get_prop(o.g, Edge(n, common), :switch) == 1
                    # This is a line going between parts
                    # with a switch. Opening the switch
                    # solves the problem.
                    return 
                    # Just returning works if only two parts
                    # overlap. It probably doesn't work
                    # if multiple parts overlap.
                end
            else
                # The line is not going between the part. If it has a
                # switch we may want to check it out later.
                if get_prop(o.g, Edge(n, common), :switch) == 1
                    push!(common_switches, Edge(n, common))
                end
            end
        end
    end
    # We have iterated over all the vertices common to the two parts
    # without splitting the network. We will now try to open switches
    # on edges between vertices in both parts.
    for e in common_switches
        rem_edge!(o.g, e)
        islands = connected_componets(o.g)
        # Since we operate radially we don't bother to check if we split
        # it two.
        if parts_split(o, island)
            # We sucessfully split the network.
            return 
        end
        # Removing the edge didn't help. Put it back
        add_edge!(g, e)
    end
    # We didn't manage to split the network using switches between the parts
    # or in the overlapping area. This means that we have to search for 
    # switches that can split the network. 
    # find_splitting_switches(o)
end

# """
    # This method searches the graph for switches that sucessfully splits the network
    # in two.
# """
# function find_parts_splitting_switches(o)
    # not_split = true
    # while not_split


# function find_part_splitting_switch

