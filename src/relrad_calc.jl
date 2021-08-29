using RelRad
using LightGraphs
using PowerGraphs
using DataFrames
using MetaGraphs
import Base.==
# using Plots, GraphRecipes

# function src(e::Tuple)
#     return e[1]
# end

# function dst(e::Tuple)
#     return e[2]
# end

struct Branch{T} <:AbstractEdge{T}
    src::T
    dst::T
end

function Branch(t::Tuple)
    Branch(t[1], t[2])
end

function reverse(edge::Branch)
    return Branch(edge.dst, edge.src)
end

(==)(e1::Branch, e2::Branch) = (e1.src == e2.src && e1.dst == e2.dst)



# reverse(e::T) where T<:Branch = T(dst(e), src(e))
# ==(e1::Branch, e2::Branch) = (src(e1) == src(e2) && dst(e1) == dst(e2))

# function src(e::Branch)
#     return e.source
# end

# function dst(e::Branch)
#     return e.dest
# end

"""
    relrad_calc(interruption::Interruption, cost_functions::Dict{String, PieceWiseCost}, network::RadialPowerGraph)

        Returns the load interruption costs

        # Arguments
        - interruption: Data Structure with customer type information
        - cost_functions: Dictionary with cost information
        - network: Data Structure with network data

        # Output
        - IC: Costs for permanent interruption, defined for each load and each failed branch
        - ICt: Costs for temporary interruption, defined for each load and each failed branch
"""
function relrad_calc(interruption::Interruption, 
                    cost_functions::Dict{String, PieceWiseCost}, 
                    network::RadialPowerGraph, 
                    filtered_branches=DataFrame(element=[], f_bus=[],t_bus=[], tag=[]))::Tuple{Array{Float64,2},Array{Float64,2},Array{Any,1},DataFrame}
    Q = []  # Empty array
	L = string.(network.mpc.loaddata.bus)
    edge_pos_df = store_edge_pos(network)
    IC = zeros(length(L), nrow(network.mpc.branch))
    ICt = zeros(length(L), nrow(network.mpc.branch))
    push_adj(Q, network.radial, 1) # I explore only the original radial topology for failures effect (avoid loops of undirected graph)
                                        # By definition the radial topology is built with 1 as root node
    # I select all the transformers
    # F = get_transformers(network)
    # I take only the first transformer (trying to assign a single supply point)
    # F = [get_transformers(network)[1]]
    # I set a dummy transformer with as secondary the desired slack bus
    # F = [RelRad.Branch("0","b74dfe84-9304-4cba-98bb-b0608706d60c")]   
    i = 0
    F = get_slack(network) # get list of substations (not distribution transformers). If not present, I use as slack the slack bus declared
    while !isempty(Q)
        e = pop!(Q)
        edge_pos = get_edge_pos(e,edge_pos_df, filtered_branches)
        rel_data = get_branch_data(network, :reldata, e.src, e.dst)
        
        IC = section(interruption, cost_functions, network, edge_pos, IC, e, L, F)
        l_pos = 0
        for l in L
            l_pos += 1
			bus_data = get_bus_data(network, l)
            ICt[l_pos, edge_pos] = calculate_kile(interruption, cost_functions,
												  float(rel_data.temporaryFaultFrequency[1]),
												  float(bus_data.Pd[1]),
												  float(rel_data.temporaryFaultTime[1])
                                    )
        end
        push_adj(Q, network.radial, e)
    end
    return IC, ICt, L, edge_pos_df
end


"""
    section(interruption::Interruption,
            cost_functions::Dict{String, PieceWiseCost},
            network::RadialPowerGraph,
            net_map::graphMap,
            IC::Array,
            e::LightGraphs.SimpleGraphs.SimpleEdge{Int64},
            L::Array)

            Performs the sectioning of the branch and returns the permanent interruption costs

            # Arguments
            - interruption: Data Structure with customer type information
            - cost_functions: Dictionary with cost information
            - network: Data Structure with network data
            - net_map:: Data structure with graph-network mapping
            - e: failed network edge
            - L: Array of loads

            # Output
            - IC: Costs for permanent interruption, defined for each load and each failed branch

"""
function section(interruption::Interruption,
        cost_functions::Dict{String, PieceWiseCost},
        network::RadialPowerGraph,
        edge_pos::Int,
        IC::Array,
        e::Branch,
        L::Array,
        F::Array)::Array{Float64,2}
    # R = calc_R(network, net_map, e)
    
    # e_original = e # Failed branch
    #sectioning_time = 0.0 # I assign a local variable that will be update within the while loop
    repair_time = get_branch_data(network, :reldata, e.src, e.dst).repairTime
    permanent_failure_frequency = get_branch_data(network, :reldata, e.src, e.dst).permanentFaultFrequency

    R_set = []

    if !is_switch(network, e.src, e.dst)
        isolated_graph, reconfigured_network, sectioning_time = traverse_and_get_sectioning_time(network, e)
        for f in F
            R = Set(calc_R(network, reconfigured_network, f))
            push!(R_set, R)
            # append!(t_sect, get_branch_data(network, :reldata, src(e), dst(e)).sectioning_time)
        end

    else
        return IC # if it is a switch, return IC as it is (switches never fail at the moment)
    end

    X = union(R_set...)

    l_pos = 0
    for l in L
        l_pos += 1
        if !(l in X) 
            t = repair_time
        else
            t = sectioning_time
        end
		bus_data = get_bus_data(network, l)
        IC[l_pos,edge_pos] = calculate_kile(interruption,
                                cost_functions,
								float(permanent_failure_frequency[1]),
								float(bus_data.Pd[1]),
								float(t[1])
                                )
    end
    return IC
end

function get_sectioning_time(isolated_graph::AbstractMetaGraph, network::RadialPowerGraph)
    sectioning_time = 0.0
    switches_iter = filter_edges(isolated_graph, (g,x)->(get_prop(g, x, :switch) >= 0))
    for switch in switches_iter
        e = edge2branch(isolated_graph, switch)
        t = get_branch_data(network, :reldata, :sectioningTime, e.src, e.dst)
		t = isnothing(t) ? get_branch_data(network, :switch, :switchingTime, e.src, e.dst)[1] : t[1]
		if t > sectioning_time
            sectioning_time = t
        end
        rem_edge!(isolated_graph, switch)
        # for v in [switch.src, switch.dst]
        #     if size(all_neighbors(isolated_graph,v))[1]==0
        #         rem_vertex!(isolated_graph,v)
        #     end
        # end
    end
    
    return sectioning_time
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
    v = get_node_number(network.G,e.dst)
    vlist = traverse(g,v)
    return [get_bus_name(network.G, bus) for bus in vlist]
end

""" Calculate reachable vertices starting from a given edge"""
function calc_R(network::RadialPowerGraph,
                g::MetaGraph,
                b::Union{String,Int})::Array{Any}
    v = get_node_number(network.G,b)
    vlist = traverse(g,v)
    return [get_bus_name(network.G, bus) for bus in vlist]
end


function traverse(g::MetaGraph, start::Int = 0, dfs::Bool = true)::Vector{Int}
    seen = Vector{Int}()
    visit = Vector{Int}([start])
    @assert start in vertices(g) "can't access $start in $(props(g, 1))"
    while !isempty(visit)
        next = pop!(visit)
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


function traverse_and_get_sectioning_time(network::RadialPowerGraph, e::Branch)
	g = network.G
    newgraph = MetaDiGraph()
	copy_g = MetaGraph(copy(g)) # This graph must be undirected
    set_indexing_prop!(newgraph, :name)
    s = get_node_number(network.G, string(e.src))
    seen = Vector{Int}([])
    visit = Vector{Int}([s])

    reindex = Dict{Int,Int}()
    i = 1
    push!(reindex, s=>i)

    add_vertex!(newgraph)
    set_prop!(newgraph, i, :name, string(e.src)) # get_prop(g, src(e), :name))

    while !isempty(visit)
        next = pop!(visit)
        if !(next in seen)
            push!(seen, next)
            for n in all_neighbors(g, next)
                e = Edge(next, n) in edges(g) ? Edge(next, n) : Edge(n, next)
                if !(n in seen) & (n != network.ref_bus)
                    if get_prop(g, e, :switch) == -1 # it is not a switch, I keep exploring the graph
                        append!(visit, n)
                    else
                        push!(seen, n) # it is a switch, I stop exploring the graph (visit does not increase)
                    end
                    i+=1
                    push!(reindex, n=>i)
                    add_vertex!(newgraph)
                    set_prop!(newgraph, reindex[n], :name, get_prop(g, n, :name))

                    add_edge!(newgraph, reindex[next], reindex[n])
                    set_prop!(newgraph, reindex[next], reindex[n], :switch, get_prop(g, e, :switch))
                    rem_edge!(copy_g, e)
                end
            end

        end
    end
    sectioning_time = get_sectioning_time(newgraph, network)
    return newgraph, copy_g, sectioning_time
end

function get_slack(network::RadialPowerGraph)::Array{Any}
    transformers = network.mpc.transformer
    F = []
    for e in eachrow(transformers)
        push!(F, Branch(e.f_bus, e.t_bus))
    end
    if isempty(F)
        F = [network.ref_bus]
    end
    return F
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
        return insertcols!(insertcols!(select(network.mpc.branch, "f_bus"=>"f_bus", "t_bus"=>"t_bus"),1,:name=>1:size(network.mpc.branch)[1]), 1,:index =>1:size(network.mpc.branch)[1])
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

function edge2branch(g::AbstractMetaGraph, e::LightGraphs.SimpleGraphs.SimpleEdge{Int64})::Branch
    s = get_bus_name(g, src(e))
    d = get_bus_name(g, dst(e))
    return Branch(s,d)
end
