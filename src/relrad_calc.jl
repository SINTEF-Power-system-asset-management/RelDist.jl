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
                    config::Traverse=Traverse(),
                    filtered_branches=DataFrame(element=[], f_bus=[],t_bus=[], tag=[]))
    Q = []  # Empty arrayjh
	L = get_loads(network.mpc)
    edge_pos_df = store_edge_pos(network)
    res = RelStruct(length(L), nrow(network.mpc.branch))
    resₜ = RelStruct(length(L), nrow(network.mpc.branch))
    push_adj(Q, network.radial, network.radial[network.ref_bus, :name])
    # I explore only the original radial topology for failures effect (avoid loops of undirected graph)
    # I select all the transformers
    # F = get_transformers(network)
    # I take only the first transformer (trying to assign a single supply point)
    # F = [get_transformers(network)[1]]
    # I set a dummy transformer with as secondary the desired slack bus
    # F = [RelRad.Branch("0","b74dfe84-9304-4cba-98bb-b0608706d60c")]   
    i = 0
    F = get_slack(network, config.consider_cap) # get list of substations (not distribution transformers). If not present, I use as slack the slack bus declared
    while !isempty(Q)
        e = pop!(Q)
        @info "Processing line $e"
        edge_pos = get_edge_pos(e,edge_pos_df, filtered_branches)
        rel_data = get_branch_data(network, :reldata, e.src, e.dst)
        
        section!(res, cost_functions, network, edge_pos, e, L, F)
        
        l_pos = 0
        for l in L

            l_pos += 1
            set_rel_res!(resₜ,
                         rel_data.temporaryFaultFrequency[1],
                         rel_data.temporaryFaultTime[1],
                         l.P,
                         cost_functions[l.type],
                         l_pos, edge_pos)
        end
        push_adj(Q, network.radial, e)
    end
    return res, resₜ, L, edge_pos_df
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
function section!(res::RelStruct,
        cost_functions::Dict{String, PieceWiseCost},
        network::RadialPowerGraph,
        edge_pos::Int,
        e::Branch,
        L::Array,
        F::Array)
    
    repair_time = get_branch_data(network, :reldata, e.src, e.dst).repairTime
    permanent_failure_frequency = get_branch_data(network, :reldata, e.src, e.dst).permanentFaultFrequency[1]

    R_set = []

    if permanent_failure_frequency >= 0
        reconfigured_network, sectioning_time = traverse_and_get_sectioning_time(network, e)
        for f in F
            R = Set(calc_R(network, reconfigured_network, f))
            push!(R_set, R)
        end

    else
        return # If the line has no permanent failure frequency we skip it.
    end

    X = union(R_set...)

    l_pos = 0
    for l in L
        l_pos += 1;false
        if !(l.bus in X) 
            t = repair_time
        else
            t = sectioning_time
        end
        set_rel_res!(res, permanent_failure_frequency, t[1],
                     l.P,
                     cost_functions[l.type],
                     l_pos, edge_pos)
    end
end

function get_sectioning_time(network::RadialPowerGraph, e::Edge)
    get_sectioning_time(network, edge2branch(network.G, e))
end

function get_sectioning_time(network::RadialPowerGraph, e::Branch)
    t = get_branch_data(network, :reldata, :sectioningTime, e.src, e.dst)
    isnothing(t) ? get_branch_data(network, :switch, :switchingTime, e.src, e.dst)[1] : t[1]
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
    traverse_and_get_sectioning_time

    Finds the switch that isolates a fault and the part of the network connected to
    this switch.
"""
function traverse_and_get_sectioning_time(network::RadialPowerGraph, e::Branch,
    switch_failures::Bool=false)
	g = network.G
	reconfigured_g = MetaGraph(copy(g)) # This graph must be undirected
    s = get_node_number(network.G, string(e.src))
    seen = Vector{Int}([])
    t_sec = 0

    n = get_node_number(network.G, e.dst)
    switch_buses = get_prop(g, Edge(s, n), :switch_buses)
    if length(switch_buses) == 2
        # Both sides of the edge have switches, the fault is therefore isolated
        # by removing this edge.
        visit =  Vector{Int}([]) # Stop the loop
        t_sec = get_sectioning_time(network, e) 
        rem_edge!(reconfigured_g, Edge(s, n))
    elseif length(switch_buses) == 1
        # Only one side of the edge has a switch, we need to continue
        # to look for swithces.
        
        # Add the edge to the isolated graph
        # Find the direction to continue the search
        s = e.src==switch_buses[1] ? get_node_number(network.G, string(e.dst)) : get_node_number(network.G, string(e.src))
        visit =  Vector{Int}([s])

        # Mark the bus with the switch as seen.
        push!(seen, get_node_number(network.G, switch_buses[1]))
        
        # Add sectioning time of the switch
        t_sec = get_sectioning_time(network, e)
        rem_edge!(reconfigured_g, Edge(s, n))
    else
        visit =  Vector{Int}([s])
    end

    while !isempty(visit)
        next = pop!(visit)
        if !(next in seen)
            push!(seen, next)
            for n in all_neighbors(g, next)
                e = Edge(next, n) in edges(g) ? Edge(next, n) : Edge(n, next)
                rem_edge!(reconfigured_g, e)
                if !(n in seen) & (n != network.ref_bus)
                    if get_prop(g, e, :switch) == -1 # it is not a switch, I keep exploring the graph
                        append!(visit, n)
                    else
                        push!(seen, n) # it is a switch, I stop exploring the graph (visit does not increase)
                        t = get_sectioning_time(network, e)
                        t_sec = t < t_sec ? t_sec : t
                    end
                end
            end

        end
    end
    return reconfigured_g, t_sec
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
