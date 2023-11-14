using Graphs
using SintPowerGraphs
using DataFrames
using MetaGraphs
using Logging
import Base.==

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

"""
    relrad_calc(cost_functions::Dict{String, PieceWiseCost}, network::RadialPowerGraph)

        Returns the load interruption costs

        # Arguments
        - cost_functions: Dictionary with cost information
        - network: Data Structure with network data

        # Output
        - res: Costs for permanent interruption, defined for each load and each failed branch
        - resₜ: Costs for temporary interruption, defined for each load and each failed branch
"""
function relrad_calc(cost_functions::Dict{String, PieceWiseCost}, 
                    network::RadialPowerGraph,
                    config::RelDistConf=RelDistConf(),
                    filtered_branches=DataFrame(element=[], f_bus=[],t_bus=[], tag=[]))
    Q = []  # Empty arrayj
	L = get_loads(network.mpc)
    edge_pos_df = store_edge_pos(network)
    res = Dict("base" => RelStruct(length(L), nrow(network.mpc.branch)),
               "temp" => RelStruct(length(L), nrow(network.mpc.branch)))

    # Set missing automatic switching timtes to zero
    network.mpc.switch.t_remote .= coalesce.(network.mpc.switch.t_remote, Inf)
    
    if config.failures.switch_failures
        for case in ["upstream", "downstream"] 
            res[case] = RelStruct(length(L), nrow(network.mpc.branch))
        end
    end
    push_adj(Q, network.radial, network.radial[network.ref_bus, :name])
    # I explore only the original radial topology for failures effect (avoid loops of undirected graph)
    i = 0
    F = get_slack(network, config.traverse.consider_cap) # get list of substations (not distribution transformers). If not present, I use as slack the slack bus declared
    while !isempty(Q)
        e = pop!(Q)
        @info "Processing line $e"
        edge_pos = get_edge_pos(e,edge_pos_df, filtered_branches)
        rel_data = get_branch_data(network, :reldata, e.src, e.dst)
        
        section!(res, cost_functions, network, edge_pos, e, L, F, config.failures.switch_failures)
        
        l_pos = 0
        for l in L

            l_pos += 1
            set_rel_res!(res["temp"],
                         rel_data.temporaryFaultFrequency[1],
                         rel_data.temporaryFaultTime[1],
                         l.P,
                         cost_functions[l.type],
                         l_pos, edge_pos)
        end
        push_adj(Q, network.radial, e)
    end
    return res, L, edge_pos_df
end


"""
    section(cost_functions::Dict{String, PieceWiseCost},
            network::RadialPowerGraph,
            net_map::graphMap,
            res::RelStruc,
            e::Graphs.SimpleGraphs.SimpleEdge{Int64},
            L::Array)

            Performs the sectioning of the branch and returns the permanent interruption costs

            # Arguments
            - cost_functions: Dictionary with cost information
            - network: Data Structure with network data
            - net_map:: Data structure with graph-network mapping
            - e: failed network edge
            - L: Array of loads
"""
function section!(res::Dict{String, RelStruct},
        cost_functions::Dict{String, PieceWiseCost},
        network::RadialPowerGraph,
        edge_pos::Int,
        e::Branch,
        L::Array,
        F::Array,
        switch_failures::Bool=false)
    
    repair_time = get_branch_data(network, :reldata, e.src, e.dst).repairTime
    permanent_failure_frequency = get_branch_data(network, :reldata, e.src, e.dst).permanentFaultFrequency[1]
    cases = switch_failures ? ["base", "upstream", "downstream"] : ["base"]


    if permanent_failure_frequency >= 0
        reconfigured_network, t_sec, isolated_edges, t_f = traverse_and_get_sectioning_time(network, e, switch_failures)
        for (i, case) in enumerate(cases)
            R_set = []
            # For the cases with switch failures we remove the extra edges
            if i > 1
                t_sec = t_f[i-1switch_failures]
                for e in isolated_edges[i-1]
                    rem_edge!(reconfigured_network, e)
                end
            end
            for f in F
                R = Set(calc_R(network, reconfigured_network, f))
                push!(R_set, R)
            end
            if i > 1
                for e in isolated_edges[i-1]
                    add_edge!(reconfigured_network, e)
                end
            end


            X = union(R_set...)

            l_pos = 0
            for l in L
                l_pos += 1;
                if !(l.bus in X) 
                    t = repair_time
                else
                    t = t_sec
                end
                set_rel_res!(res[case], permanent_failure_frequency, t[1],
                             l.P,
                             cost_functions[l.type],
                             l_pos, edge_pos)
            end
        end
    else
        return # If the line has no permanent failure frequency we skip it.
    end
end

function get_switching_time(network::RadialPowerGraph, e::Edge)
    get_switching_time(network, edge2branch(network.G, e))
end

function get_switching_time(network::RadialPowerGraph, e::Branch)
    get_switching_time(network.mpc, e)
end

function get_switching_time(mpc::Case, e::Branch)
    switches = mpc.switch[mpc.switch.f_bus.==e.src .&& mpc.switch.t_bus.==e.dst, :]
    if any(switches.t_remote.==Inf)
        return findmax(switches.t_manual)[1]
    else
        return findmax(switches.t_remote)[1]
    end
end

function get_names(mg)
    names = []
    for bus in 1:nv(mg)
        append!(names, [get_prop(mg, bus, :name)])
    end
    return names
end

function myplot(network, names)
    graphplot(network, names = names, nodeshape=:circle, nodesize=0.1, curves=false, fontsize=7)
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
        feeder_cap::Real=Inf, dfs::Bool = true)::Vector{Int}
    seen = Vector{Int}()
    visit = Vector{Int}([start])
    load = 0

    @assert start in vertices(g) "can't access $start in $(props(g, 1))"
    while !isempty(visit)
        next = pop!(visit)
        load += get_prop(g, next, :load)
        if load > feeder_cap
            return seen
        end
        if !(next in seen)
            for n in neighbors(g, next)
                if !(n in seen)
                    if dfs append!(visit, n) else insert!(visit, 1, n) end
                end
            end
            push!(seen, next)
        end
    end
    return seen
end

"""
    Traverse the in a direction until all isolating switches are found.
"""
function find_isolating_switches(network::RadialPowerGraph, g::MetaDiGraph,
        reconfigured_network::MetaGraph, visit::Vector{Int}, seen::Vector{Int},
        switch_found::Bool, switch_failures::Bool=false)
    # Initialise variable to keep track of sectioning time
    t_sec = 0
    t_s_failed = 0
    isolated_edges = []
   
    # If we already have found a switch we should already mark it as failed.
    if switch_found
        # Variable to keep track of whether or not to change the configured
        # network or not.
        switch_failed = true
    else
        switch_failed = false
    end
    while !isempty(visit)
        next = pop!(visit)
        if !(next in seen)
            push!(seen, next)
            for n in all_neighbors(g, next)
                e = Edge(next, n) in edges(g) ? Edge(next, n) : Edge(n, next)
                
                #  In case a switch has already failed we add the edge to a list
                #  of failed edges. If no edges have failed previously we modfiy
                #  the reconfigured_network
                if switch_failed
                    push!(isolated_edges, e)
                else
                    rem_edge!(reconfigured_network, e)
                end
                if !(n in seen) & (n != network.ref_bus)
                    if get_prop(g, e, :switch) == -1 # it is not a switch, I keep exploring the graph
                        append!(visit, n)
                    else
                        # We have found a switch
                        switch_found = true
                        if !switch_failures || switch_failed
                            # it is a switch, I stop exploring the graph (visit does not increase)
                            push!(seen, n) 
                        end
                        
                        if switch_failed 
                            # We are past the depth of the first isolating switch(es)
                            t = get_switching_time(network, e)
                            t_s_failed = t < t_s_failed ? t_s_failed : t
                        else
                            # We are at the depth of the first isolating switch(es)
                            t = get_switching_time(network, e)
                            t_sec = t < t_sec ? t_sec : t
                        end
                    end
                end
            end
            if switch_found
                # We found a switch at this depth. We don't have to go deeper.
                switch_failed = true
            end
        end
    end
    return t_sec, isolated_edges, t_s_failed
end

"""
    traverse_and_get_sectioning_time

    Finds the switch that isolates a fault and the part of the network connected to
    this switch.
"""
function traverse_and_get_sectioning_time(network::RadialPowerGraph, e::Branch,
    switch_failures::Bool=false)
    # isolated_edges = []
	g = network.G
	reconfigured_network = MetaGraph(copy(network.G)) # This graph must be undirected
    s = get_node_number(network.G, string(e.src))

    n = get_node_number(network.G, e.dst)
    switch_buses = get_prop(g, Edge(s, n), :switch_buses)
    # If we consider switch failures we always have to search up and
    # downstream.
    if switch_failures
        visit_u = Vector{Int}([s])# Vertices to check upstream
        visit_d =  Vector{Int}([n])# Vertices to check downstream
    else
        visit_u =  Vector{Int}([]) # Vertices to check upstream
        visit_d =  Vector{Int}([]) # Vertices to check downstream
    end
    
    switch_src = true # There is a switch at the source
    switch_dst = true # There is a switch at the destination
    if length(switch_buses) >= 1
        # There is at least one switch on the branch
        if e.src ∉ switch_buses
            # There is no switch at the source, we have to search upstream
            visit_u = Vector{Int}([s])
            switch_src = false
        end
        if e.dst ∉ switch_buses
            # There is no switch at the destination, we have to search downstream
            visit_d = Vector{Int}([n])
            switch_dst = false
        end
            
        t_sec = get_switching_time(network, e) 
    else
        visit_u =  Vector{Int}([s])
        visit_d =  Vector{Int}([n])
        switch_src = false
        switch_dst = false
        t_sec = 0
    end
    rem_edge!(reconfigured_network, Edge(s, n))
    # Search upstream
    t, isolated_upstream, t_upstream = find_isolating_switches(
                                        network, g, reconfigured_network, visit_u, copy(visit_d),
                                        switch_src, switch_failures)
    t_sec = t_sec > t ? t_sec : t
    
    # Search downstream
    t, isolated_downstream, t_downstream = find_isolating_switches(
                                        network, g, reconfigured_network, visit_d, copy(visit_u),
                                        switch_dst, switch_failures)
    return reconfigured_network, t_sec > t ? t_sec : t, [isolated_upstream, isolated_downstream], [t_upstream, t_downstream]
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
        F = [Feeder(network.ref_bus,
                    consider_cap ? get_feeder_cap(network, network.ref_bus) : Inf)]
        for reserve in network.reserves
            append!(F,
                    Feeder(reserve,
                           consider_cap ? get_feeder_cap(network, feeder) : Inf))
        end
    end
    return F
end

""""
    Returns the capacity of a feeder.
"""
function get_feeder_cap(network::RadialPowerGraph, feeder::String)::Real
    network.mpc.gen[network.mpc.gen.bus.==network.ref_bus, :Pmax][1]
end

function are_edges_equal(e_input, e_test)::Bool
    return e_input == e_test || e_input == reverse(e_test)
end


function push_adj(Q::Array{Any,1}, g::AbstractMetaGraph, v::Int)
    # it takes as input the graph VERTEX v, it stores in Q the list of Power BRANCHES adjacent of v
    successors = neighbors(g, v)
    for i in successors
        push!(Q, edge2branch(g, Edge(v,i))) # Edge(get_bus_name(network,v), get_bus_name(network,i)))
    end
end

function push_adj(Q::Array{Any,1}, g::AbstractMetaGraph, e::Branch)
    v = get_node_number(g, e.dst) # t_bus in the graph notation
    push_adj(Q, g, v)
end

function get_bus_name(g, vertex)
	 g[vertex, :name]
end

function get_node_number(g, bus)
    g[bus, :name]
end

function store_edge_pos(network::RadialPowerGraph)
    if "name" in names(network.mpc.branch)
        return insertcols!(select(network.mpc.branch, "f_bus"=>"f_bus", "t_bus"=>"t_bus", "name"=>"name"), 1,:index =>1:size(network.mpc.branch)[1])
    elseif "ID" in names(network.mpc.branch)
        return insertcols!(select(network.mpc.branch, "f_bus"=>"f_bus", "t_bus"=>"t_bus", "ID"=>"name"), 1,:index =>1:size(network.mpc.branch)[1])
    else
        # Here I am creating artificially a name column equal to the index
        return insertcols!(insertcols!(select(network.mpc.branch, "f_bus"=>"f_bus", "t_bus"=>"t_bus"),1,:name=>string.(1:size(network.mpc.branch, 1))), 1,:index =>1:size(network.mpc.branch)[1])
    end
end

function get_edge_pos(e, edge_pos, filtered_branches)
    if typeof(edge_pos.f_bus[1])==Int
        rows = vcat(edge_pos[.&(edge_pos.f_bus.==parse(Int64,e.src), edge_pos.t_bus.==parse(Int64,e.dst)),:],
            edge_pos[.&(edge_pos.f_bus.==parse(Int64,e.dst), edge_pos.t_bus.==parse(Int64,e.src)),:])
    else
        rows = vcat(edge_pos[.&(edge_pos.f_bus.==e.src, edge_pos.t_bus.==e.dst),:],
            edge_pos[.&(edge_pos.f_bus.==e.dst, edge_pos.t_bus.==e.src),:])
    end
    for row in collect(eachrow(rows))
        if !(row.name in filtered_branches[!,:element])
            return row.index 
        end
    end
end

function edge2branch(g::AbstractMetaGraph, e::Graphs.SimpleGraphs.SimpleEdge{Int64})::Branch
    s = get_bus_name(g, src(e))
    d = get_bus_name(g, dst(e))
    return Branch(s,d, get_prop(g, src(e), dst(e), :rateA))
end
