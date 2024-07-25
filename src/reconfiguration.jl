using OrderedCollections

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
    shed::Bool
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
            get_prop(g, v, :external), false)
    else
        return Gen(get_prop(g, v, :name), 0.0, false, false)
    end
end

mutable struct Part
    capacity::Real

    tot_load::Real

    shed_load::Real

    tot_gen::Real

    shed_gen::Real

    loads::Dict{Int,Loadr}

    gens::Dict{Int,Gen}

    vertices::Vector{Int}

    switches::Vector{Switch}
end

function Part()
    Part(0.0, 0.0, 0.0, 0.0, 0.0,
        Dict{Int,Loadr}(), Dict{Int,Gen}(),
        Vector{Int}(), Vector{Switch}())
end

function Part(capacity::Real, v_start::Integer)
    Part(capacity, 0.0, 0.0, 0.0, 0.0,
        Dict{Int,Loadr}(), Dict{Int,Gen}(),
        Vector([v_start]), Vector{Switch}())
end

function Part(capacity::Real, load::Loadr, gen::Gen, v_start::Integer)
    Part(capacity, 0.0, 0.0, 0.0, 0.0,
        Dict(v_start => load), Dict(v_start => gen),
        Vector([v_start]), Vector{Switch}())
end

"""
    Returns the load in a set of vertices that are in a part.
"""
function load_in_part_vertices(part::Part, vertices::Vector{Int})
    sum(part.loads[v].P for v in vertices; init=0.0)
end

"""
    Returns the total load in two parts.
"""
function load_in_parts(part_a::Part, part_b::Part)
    (load_in_part_vertices(part_a, setdiff(part_a.vertices, part_b.vertices)) +
     load_in_part_vertices(part_b, setdiff(part_b.vertices, part_a.vertices)) +
     load_in_part_vertices(part_a, intersect(part_a.vertices, part_b.vertices)))
end

"""
    returns the source vertex of a part.
"""
function source(part::Part)
    first(part.vertices)
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
    part.loads[v] = load
    part.gens[v] = gen
    part.tot_load += load.P
    part.tot_gen += gen.P

    push!(part.vertices, v)
end

function remove_vertex!(part::Part, v::Integer)
    shed_load!(part, v)
    shed_gen!(part, v)
    pop!(part.vertices)
    pop!(part.gens, v)
    pop!(part.loads, v)
end

"""
    Sheds the load on the vertices
"""
function shed_load!(part::Part, vertices::Vector{Int})
    for vertex in vertices
        shed_load!(part, vertex)
        shed_gen!(part, vertex)
    end
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

"""
    Check if a vertex is in a part.
"""
function Base.:∈(v::Int, part::Part)
    v ∈ part.vertices
end

"""
    Reconnect load on vertex v.
"""
function reconnect_load!(part::Part, v::Int)
    part.loads[v].shed = false
    part.tot_load += part.loads[v].P
    part.shed_load -= part.loads[v].P
end

"""
    Reconnect load on vertices v.
"""
function reconnect_load!(part::Part, vertices::Vector{Int})
    for v in vertices
        reconnect_load!(part, v)
    end
end

""""
    Shed load in sources.
"""
function shed_load!(part::Part, load::Loadr)
    load.shed = true
    part.tot_load -= load.P
    part.shed_load += load.P
end

function shed_load!(part::Part, v::Int)
    # Not sure if this is the best way to handle it.
    # Anyways, before this method is called, it is 
    # possible that I alrady shed some load
    if !part.loads[v].shed
        shed_load!(part, part.loads[v])
    end
end

""""
    Shed gen in part.
"""
function shed_gen!(part::Part, gen::Gen)
    # Implement when I need it.
end

function shed_gen!(part::Part, v::Int)
    # Implement when I need it.
end

"""
    Returns the names of the loads that are in service.
"""
function in_service_loads(part::Part)
    # If there is no distributed generation in the part, everything
    # that is not shed can be supplied for the full duration of
    # the fault repair.
    if part.tot_gen == 0
        Dict(load.bus => Inf for load in values(part.loads) if !load.shed)
    end
end

"""
    Returns true if any load has been shed.
"""
function any_shed(part::Part)
    for load in values(part.loads)
        if load.shed
            return true
        end
    end
    return false
end

"""
    Returns true if the part could not serve all loads it
    could reach.
"""
function not_all_served(part::Part)
    any_shed(part) || !isempty(part.switches)
end

"""
    Returns the loading of a part

    This version is quite simple and merely uses the algebraic sum
    of consumption and production.
"""
function loading(part::Part)
    part.tot_load - part.tot_gen
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

function traverse(network::RadialPowerGraph, g::MetaGraph, start::Int=0,
    feeder_cap::Real=Inf, seen=Vector{Int}())
    part = Part(feeder_cap,
        get_load(g, network.mpc, start),
        get_gen(g, network.mpc, start),
        start)
    traverse!(network, g, part, start, seen)
    return part
end

function traverse!(network::RadialPowerGraph, g::MetaGraph, part::Part, start::Int=0,
    seen=Vector{Int}())
    @assert start in vertices(g) "can't access $start in $(props(g, 1))"

    parents = Dict{Int,Int}()
    visit = Vector{Int}([start])

    while !isempty(visit)
        v_src = pop!(visit)
        if (v_src in seen)
            continue
        end
        push!(seen, v_src)
        for v_dst in setdiff(all_neighbors(g, v_src), seen)
            e = Edge(v_src, v_dst)

            load = get_load(g, network.mpc, v_dst)
            gen = get_gen(g, network.mpc, v_dst)
            update_part!(part, gen, load, v_dst)

            # Check if we have reached the capacity of the feeder connected to the part
            overload = loading(part) - part.capacity

            if overload <= 0
                # There was no overload update the part and continue
                # the search.
                append!(visit, v_dst)
                continue
            end

            for temp_load in values(part.loads) # can probably overload something to make this cleaner
                # Shed nfc that has not been sked
                if temp_load.nfc && !temp_load.shed
                    shed_load!(part, temp_load)
                    if loading(part) - part.capacity < 0
                        # We removed the overload stop shedding
                        break
                    end
                end
            end
            # Check if we managed to solve the overload by shedding ncf
            overload = loading(part) - part.capacity

            if overload <= 0
                # There was no overload update the part and continue
                # the search.
                append!(visit, v_dst)
                continue
            end

            if get_prop(g, e, :switch) == 1
                # This is a switch, we give up
                push!(part.switches, get_switch(network, e))
                remove_vertex!(part, v_dst)
            else
                # This is not a switch, we have to update the part,
                # shed the load and continue the search
                shed_load!(part, v_dst)
                append!(visit, v_dst)
            end
        end
    end
end

mutable struct Overlapping
    network::RadialPowerGraph
    g::MetaGraph
    parts::Vector{Part}
    part::Part
    old_p::Part
    old_i::Int
    overlapping::Vector{Int}
    add_new_part::Bool
    tot_load::Real
end

function Overlapping(network::RadialPowerGraph, g::MetaGraph, parts::Vector{Part}, part::Part)
    Overlapping(network, g, parts, part, Part(), 0, Vector{Int}(), true, 0)
end

function update_overlapping!(o::Overlapping, old_p::Part,
    old_i::Int, overlapping::Vector{Int})
    o.old_p = old_p
    o.old_i = old_i
    o.overlapping = overlapping
    o.tot_load = load_in_parts(o.part, old_p)
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

function islands_in_parts(o::Overlapping, i_1::Vector{Int}, i_2::Vector{Int})
    reserve_in_island(o.part, i_1) && reserve_in_island(o.old_p, i_2)
end

mutable struct Split
    vertices::Vector{Int}
    reconnect::Vector{Int}
    P::Real
end

function Split()
    Split(Vector{Vector}{Int}(), Dict{Int,Real}, 0)
end

"""
    Finds the islands that the parts are in.
"""
function find_parts_in_islands(part::Part, islands::Vector{Vector{Int}})

    for island in islands
        if reserve_in_island(part, island)
            return Split(island, Vector{Int}(), 0.0)
        end
    end
end

"""
    This function takes in a Split and a Part. It then check
    if the split allows some loads to be reconnected. It also
    checks how much load can be served in the Part given the Split.
"""
function evaluate_split!(split::Split, part::Part)
    # Calculate amount of power that will no longer be in the Part after the Split
    v_diff = setdiff(part.vertices, split.vertices)
    if isempty(v_diff)
        return
    end
    # This is probably not correct. Because none of this may solve the overload.
    recon_P = sum(part.loads[v].P for v in v_diff if !part.loads[v].shed; init=0.0)

    # Iterate the vertices in the Part after the Split. Note that the split
    # May contain vertices that are not in the Part. We currently do, not
    # check if they can be readded.
    for v in intersect(split.vertices, part.vertices)
        power = part.loads[v].P
        # If the load was never shed, count it as being served
        if !part.loads[v].shed
            split.P += power
        else
            # If the load was shed, but its power is smaller
            # than what can be reconnect, reconnect it.
            if power <= recon_P
                append!(split.reconnect, v)
                split.P += power
            end
        end
    end
end

function parts_split(o::Overlapping, islands::Vector{Vector{Int}})
    # Since the function finding the isolating switches only remove
    # edges, we may have more than 3 islands. This could be fixed
    # later.
    reserves_found = 0
    for isl in islands
        old_p_in_isl = reserve_in_island(o.old_p, isl)
        p_in_isl = reserve_in_island(o.part, isl)
        if old_p_in_isl && p_in_isl
            # If both reserves can reach the island
            # we didn't split the netwok
            return false
        elseif p_in_isl || old_p_in_isl
            # One of the reserves were in the island
            # increase the counter.
            reserves_found += 1
        end
    end
    # If we sucessfully split the network we found two
    # reserves
    return reserves_found == 2
end

function check_overlap_and_fix!(network::RadialPowerGraph, g::MetaGraph,
    parts::Vector{Part}, part::Part)
    o = Overlapping(network, g, parts, part)
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
    # Or if the new part is a subset of a part that has served all loads
    if vertices_equal(o)
        return fix_parts_with_same_vertices!(o)
        # Here we check if one part is a subset of the other
        # I am not sure how realistic this is, but nice to
        # be certain.
    elseif part_is_subset(o) && !not_all_served(o.old_p)
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

"""
    Check if we found a split that solved all shedding in the parts.
"""
function split_solved_overlap(o::Overlapping, splits_temp::Dict{Symbol,Split})
    return o.tot_load == splits_temp[:part].P + splits_temp[:old_p].P
end

function find_reconfiguration_switches!(o::Overlapping)
    # Variable to keep track of the best split
    splits = Dict{Symbol,Split}()
    splits_temp = Dict{Symbol,Split}()
    solved = false
    best_P = 0
    islands = Vector{Vector{Int}}()
    split_switch = Switch()
    # We could reduce the running time by first considering the overlap of the
    # vertices that both parts can supply.
    for common in o.overlapping
        for n in all_neighbors(o.g, common)
            # Previously I first checked the lines going between the parts first.
            # It seems that this was not a good strategy. Now I will just check
            # the lines connected to vertices that are common.
            e = Edge(n, common)
            if get_prop(o.g, e, :switch) == 1
                # Check if opening the switch sucessfully split the netwok.
                islands = islands_after_switching(o, e)
                if parts_split(o, islands)
                    # We sucessfully split the netowrk
                    power = 0
                    for part in [:part, :old_p]
                        temp_part = getfield(o, part)
                        split_temp = find_parts_in_islands(temp_part, islands)
                        evaluate_split!(split_temp, temp_part)
                        # Check if the splitting resulted in all loads being reconnected
                        power += split_temp.P
                        splits_temp[part] = split_temp
                    end

                    if split_solved_overlap(o, splits_temp)
                        for (part, split) in splits_temp
                            reconnect_load!(getfield(o, part), split.reconnect)
                        end
                        return
                    end
                    if best_P < power
                        splits = splits_temp
                        best_P = power
                        split_switch = get_switch(o.network, e)
                    end
                end
            end
        end
    end
    if best_P == 0
        # We didn't manage to split the network using switches between the parts
        # or in the overlapping area. This means that we have to search for 
        # switches that can split the network. 
        find_parts_splitting_switches(o)
    else
        for (part, split) in splits
            reduce_part_after_reconf!(getfield(o, part), o.g, splits[part].vertices)
            reconnect_load!(getfield(o, part), split.reconnect)
            push!(getfield(o, part).switches, split_switch)
        end
        return
    end
end

"""
    When parts are ovelapping, opening a switch will result
    in at least one part becoming smaller. This code will
    fix this.
"""
function reduce_part_after_reconf!(part::Part, g::MetaGraph, island::Vector{Int})
    for v in setdiff(part.vertices, island)
        remove_vertex!(part, v)
    end
    # After removing the vertices we may end up in a situation where one
    # of the vertices splitting the part from the rest of the network no
    # longer is in the part.
    del_swithces = Vector{Int}()
    for (idx, switch) in enumerate(part.switches)
        if !any(in.([g[switch.src, :name], g[switch.dst, :name]], Ref(part.vertices)))
            # The switch is not in the part, we should get rid of it.
            append!(del_swithces, idx)
        end
    end
    deleteat!(part.switches, del_swithces)
end

function islands_after_switching(o::Overlapping, e::Edge)
    # When I remove the edge I lose the properties of the
    # edge. I therefore create a copy of the graph to work on.
    # There may be a faster way of doing this.
    temp_g = copy(o.g)
    rem_edge!(temp_g, e)
    islands = connected_components(temp_g)
    return islands
end

"""
    This method searches the graph for switches that sucessfully splits the network
    in two.
"""
function find_parts_splitting_switches(o::Overlapping)
    switches = Dict{Part,Switch}()
    for part in [o.part, o.old_p]
        seen = copy(overlapping)
        visit = Vector{Int}([source(part)])
        while !isempty(visit)
            v_src = pop!(visit)
            if !(v_src in seen)
                push!(seen, v_src)
                for v_dst in setdiff(all_neighbors(o.g, v_src), seen)
                    e = Edge(v_src, v_dst)
                    if get_prop(o.network.G, e, :switch) == 1
                        # We found a switch, we can try to open it.
                        islands = islands_after_switching(o, e)
                        # We could make a faster test here, since we know that
                        # our part is in one of the islands
                        if parts_split(o, islands)
                            # We seem to be on a branch that splits the network.
                            # we should keep looking in this direction.
                            append!(visit, v_dst)

                            # Remember the switch we found
                            switches[part] = get_switch(o.network, e)
                        end
                    else
                        # It is not a switch, we should continue the search.
                        append!(visit, v_dst)
                    end
                end
            end
        end
        # Remove vertices we didn't see.
        shed_load!(part, part_vertices_not_in_vertices(part, seen))
        push!(part.switches, switches[part])
    end
end

"""
    Evaluate the parts of the network we haven't investigated so far.
"""
function evaluate_unpartitioned_parts!(network::RadialPowerGraph,
    g::MetaGraph, parts::Vector{Part})
    seen = vcat([part.vertices for part in parts]...)
    for part in parts
        for switch in part.switches
            switch_v = [g[switch.src, :name], g[switch.dst, :name]]
            # If the vertices of the switch edge is in more than one part
            # this is a switch splitting parts and we should not search from it.
            starts = setdiff(switch_v, part.vertices)
            if isempty(starts)
                starts = setdiff(
                    vcat([all_neighbors(g, v) for v in switch_v]...), part.vertices)
            end
            # In case the splitting switch is right before an intersection we have
            # will have more than one direction to evaluate.
            for start in starts
                if sum(any(switch_v' .∈ part.vertices) for part in parts) > 1
                    traverse!(network, g, part, start, seen)
                end
            end
        end
    end
end
