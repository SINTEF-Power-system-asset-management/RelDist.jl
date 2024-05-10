using Graphs
using SintPowerGraphs
using DataFrames
using MetaGraphs
using Logging
using OrderedCollections


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
                    corr_factors::Dict{String, <:Real},
                    network::RadialPowerGraph,
                    config::RelDistConf=RelDistConf(),
                    filtered_branches=DataFrame(element=[], f_bus=[],t_bus=[], tag=[]))
    Q = []  # Empty arrayj
	L = get_loads(network.mpc, corr_factors)
    edge_pos_df = store_edge_pos(network)
    res = Dict("temp" => RelStruct(length(L), nrow(network.mpc.branch)))
    # Set missing automatic switching timtes to zero
    network.mpc.switch.t_remote .= coalesce.(network.mpc.switch.t_remote, Inf)

    # Define the cases we are going to run
    cases = ["base"]
    
    # the probability of the base case if we don't have any other cases.
    base_prob = 1
    
    if config.failures.switch_failure_prob > 0
        for case in ["upstream", "downstream"] 
            res[case] = RelStruct(length(L), nrow(network.mpc.branch),
                                 config.failures.switch_failure_prob)
            push!(cases, case)
            base_prob -= config.failures.switch_failure_prob
        end
    end
    
    if config.failures.communication_failure_prob > 0
        # This case is not run in the section function. I therefore,
        # don't add it to the  case list.
        res["comm_fail"] = RelStruct(length(L), nrow(network.mpc.branch),
                                    config.failures.communication_failure_prob)
        base_prob -= config.failures.communication_failure_prob
    end

    push_adj(Q, network.radial, network.radial[network.ref_bus, :name])
    # I explore only the original radial topology for failures effect (avoid loops of undirected graph)
    i = 0
    F = get_slack(network, config.traverse.consider_cap) # get list of substations (not distribution transformers). If not present, I use as slack the slack bus declared
    
    if config.failures.reserve_failure_prob > 0
        for f in F
            if !slack_is_ref_bus(network, f)
                name = "reserve_"*create_slack_name(f)
                res[name] = RelStruct(length(L), nrow(network.mpc.branch),
                                     config.failures.reserve_failure_prob)
                push!(cases, name)
                base_prob -= config.failures.reserve_failure_prob
            end
        end
    end

    res["base"] = RelStruct(length(L), nrow(network.mpc.branch))

    
    while !isempty(Q)
        e = pop!(Q)
        @info "Processing line $e"
        edge_pos = get_edge_pos(e,edge_pos_df, filtered_branches)
        rel_data = get_branch_data(network, :reldata, e.src, e.dst)
        
        section!(res, cost_functions, network, edge_pos, e, L, F, cases, config.failures)
        
        l_pos = 0
        for l in L

            l_pos += 1
            set_rel_res!(res["temp"],
                         rel_data.temporaryFaultFrequency[1],
                         rel_data.temporaryFaultTime[1],
                         l.P,
                         l.corr,
                         cost_functions[l.type],
                         l_pos, edge_pos)
        end
        push_adj(Q, network.radial, e)
    end
    return res, L, edge_pos_df
end

function relrad_calc(cost_functions::Dict{String, PieceWiseCost},
                    network::RadialPowerGraph,
                    config::RelDistConf=RelDistConf(),
                    filtered_branches=DataFrame(element=[], f_bus=[],t_bus=[], tag=[]))
    relrad_calc(cost_functions, 
                Dict(key=>1.0 for key in keys(cost_functions)),
                network,
                config,
                filtered_branches)
end


function relrad_calc(cost_functions::Dict{String, PieceWiseCost},
                    network::RadialPowerGraph,
                    time::String,
                    config::RelDistConf=RelDistConf(),
                    filtered_branches=DataFrame(element=[], f_bus=[],t_bus=[], tag=[]))
    
        corr_fac = read_correction_factors_from_csv(MONTH_FACTORS,
                                                    DAY_FACTORS,
                                                    HOUR_FACTORS)
    if time == "year"
        corr = Dict{String, Real}()
         for cust_type in keys(cost_functions)
             corr[cust_type] = sum(get_corr_factor(corr_fac,
                                                   DateTime(t[1], t[2], t[3]),
                                                   cust_type) for t in eachrow(create_opal_year()))/2016
         end
    else
        date = DateTime(time)
        corr = Dict(key=>get_corr_factor(corr_fac, date, key) for key in keys(cost_functions))
    end
        relrad_calc(cost_functions, 
                    corr,
                    network,
                    config,
                    filtered_branches)
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
        cases::Array,
        failures::Failures)
    
    repair_time = get_branch_data(network, :reldata, e.src, e.dst).repairTime
    permanent_failure_frequency = get_branch_data(network, :reldata, e.src, e.dst).permanentFaultFrequency[1]

    if permanent_failure_frequency >= 0
        rn, isolating = traverse_and_get_sectioning_time(network, e, failures.switch_failure_prob>0)
        for case in cases
            R_set = []
            vertices = Vector{Set{Int}}()
            # For the cases with switch failures we remove the extra edges
            if case ∈ ["upstream", "downstream"]
                switches = isolating[case]
                reconfigured_network = rn[case]
            else
                switches = isolating["base"]
                reconfigured_network = rn["base"]
            end
            isolating_switch = Switch()
            for switch in switches
                isolating_switch = isolating_switch < switch ? switch : isolating_switch
            end

            for f in F
                parts = Dict{typeof(f), Part}()
                # If we are considering reserve failures and the name of the reserve
                # is the same as the case, we will skip to add the reachable loads
                # to the reachable matrix.
                if !(failures.reserve_failure_prob > 0.0 && "reserve_"*create_slack_name(f) == case)
                    part = calc_R(network, reconfigured_network, f)
                    
                    if any_shed(part)
                        # If we have shed any load we should check whether what
                        # the part can supply overlaps with what another reserve
                        # can supply
                        overlapping_reserves!(parts, part)
                    else
                        parts[f] = part
                    end
                    # Create a set of loads that are in service in the part
                    loads = Set(in_service_loads(parts[f])) 
                    push!(R_set, loads)
                end
            end
            X = union(R_set...)

            l_pos = 0
            for l in L
                l_pos += 1;
                if !(l.bus in X) 
                    t = repair_time
                else
                    t = get_minimum_switching_time(isolating_switch)
                end
                set_rel_res!(res[case], permanent_failure_frequency, t[1],
                             l.P, l.corr, cost_functions[l.type],
                             l_pos, edge_pos)
                # In case we are considering communication failures we have the same 
                # isolated network as in the base case. 
                if failures.communication_failure_prob > 0 && case == "base"
                    # In case we the outage time is not equal to the component repair time 
                    # set it to the manual switching time of the isolating switch.
                    if  t != repair_time 
                        t = isolating_switch.t_manual
                    end
                    set_rel_res!(res["comm_fail"], permanent_failure_frequency,
                                 t[1], l.P, l.corr, cost_functions[l.type],
                                 l_pos, edge_pos)
                end
            end
        end
    else
        return # If the line has no permanent failure frequency we skip it.
    end
end

function overlapping_reserves!(parts::Union{Dict{Feeder, Part}, Dict{Branch, Part}},
        part::Part)
    for (old_f, old_p) in parts
        overlapping = intersect(old_p, part)
        if length(overlapping) > 0
        # old_p is overlapping with part. First we check if there is 
        # a complete overlap. Or if one part is a subset of the other.
        # In these cases we just disregard one of the parts. Although,
        # in cases with renewables a reconfiguration may be more
        # optimal.
            if old_p.vertices == part.vertices
               # The reserves cover the same vertices. We keep the one
               # that has the largest 
               if old_p.capacity < part.capacity
                   # The new part has a better capacity.
                   # Kick out the old one
                    delete!(parts, old_f)
                    parts[f] = part
                end
                # We don't need to do anything in the oposite case
                                    
                # Here we check if one part is a subset of the other
                # I am not sure how realistic this is, but nice to
                # be certain.
            elseif subset(old_p, part)
                # The old part is a subset of part. We kick
                # out the old part. 
                delete!(parts, old_f)
                parts[f] = part
            elseif subset(part, old_p)
                # The part is a subset of the old part. We don't
                # add the new part.
            else
                # old_p an part are not subsets of each other. This means
                # that we need to determine whether it is possible to
                # split them.
                for common in overlapping
                    for n in all_neighbors(g, common)
                        if (n ∉ part.vertices || n ∉ old_p.vertices)
                            # This is a line going between the parts
                            if get_prop(g, Edge(n, common), :switch) == 1
                                # This is a line going between parts
                                # with a switch. Opening the switch
                                # solves the problem.
                                break
                                # Just breaking works if only two parts
                                # overlap. It probably doesn't work
                                # if multiple parts overlap.
                            end
                        end
                    end
                end
            end
        end
    end
end

function get_switch(network::RadialPowerGraph, e::Edge)
    get_switch(network, edge2branch(network.G, e))
end

function get_switch(network::RadialPowerGraph, e::Branch)
    get_switch(network.mpc, e)
end

function get_switch(mpc::Case, e::Branch)
    switches = mpc.switch[mpc.switch.f_bus.==e.src .&& mpc.switch.t_bus.==e.dst, :]
    if isempty(switches)
        return Switch(e.src, e.dst, -Inf, -Inf)
    end
    # If any of the swithces are not remote. I assume that the slowest switch
    # available for siwtching is a manual switch. If all swithces are remote
    # I assume that the slowst switch is a remote switch
    drop_switch = switches.t_remote.==Inf
    if any(drop_switch)
        # There is at least one switch that is not remote
        idx = findmax(switches[drop_switch, :t_manual])[2]
        switch = switches[drop_switch, :][idx, :]
    else
        idx = findmax(switches.t_remote)[2]
        switch = switches[idx, :]
    end
    return Switch(switch.f_bus, switch.t_bus, switch.t_manual, switch.t_remote)
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
"""
    Traverse the in a direction until all isolating switches are found.
"""
function find_isolating_switches!(network::RadialPowerGraph,
        reconfigured_network::MetaGraph, isolating_switches,
        visit::Vector{Int}, seen::Vector{Int})
    # Initialise variable to keep track of sectioning time
  
    while !isempty(visit)
        next = pop!(visit)
        if !(next in seen)
            push!(seen, next)
            for n in setdiff(all_neighbors(network.G, next), seen)
                e = Edge(next, n) in edges(network.G) ? Edge(next, n) : Edge(n, next)
                
                rem_edge!(reconfigured_network, e)
  
                if get_prop(network.G, e, :switch) == -1 # it is not a switch, I keep exploring the graph
                    append!(visit, n)
                else
                    # it is a switch, I stop exploring the graph in this direction
                    push!(seen, n) 
                    # We are at the depth of the first isolating switch(es)
                    push!(isolating_switches, get_switch(network, e))
                end
            end
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
    # isolated_edges = []
    rn = Dict("base" => copy(network.G)) # This graph must be undirected
    
    s = get_node_number(network.G, string(e.src))
    n = get_node_number(network.G, e.dst)
    # Remove the edge from the reconfigured network
    rem_edge!(rn["base"], Edge(s, n))
    switch_buses = get_prop(network.G, Edge(s, n), :switch_buses)
    switch_u = Vector{Switch}()
    switch_d = Vector{Switch}()
   
    seen = Vector{Int}()

    # There is at least one switch on the branch
    if e.src ∈ switch_buses
        # There is a switch at the source, we don't have to search upstream
        push!(switch_u, get_switch(network, e))

        append!(seen, s)
    else
        # Search upstream for a switch
        temp = find_isolating_switches!(network, rn["base"],
                                        switch_u, [s], [n])
        append!(seen, temp)
    end
    if e.dst ∈ switch_buses
        # There is a switch at the destination, we don't have to search downstream
        push!(switch_d, get_switch(network, e))
        append!(seen, n)
    else
        # Search upstream for a switch
        temp = find_isolating_switches!(network, rn["base"], 
                                        switch_d, [n], [s])
        append!(seen, temp)
    end
    isolating = Dict("base" => vcat(switch_u, switch_d))

    rn["upstream"] = copy(rn["base"])
    rn["downstream"] = copy(rn["base"])
    if switch_failures
        if switch_u==switch_d
            # Find backup switch upstream
            isolating["upstream"] = Vector{Switch}()
            find_isolating_switches!(network, rn["upstream"], 
                                    isolating["upstream"], [s], [n])
            
            isolating["downstream"] = Vector{Switch}()
            find_isolating_switches!(network, rn["downstream"], 
                                     isolating["downstream"], [n], [s])
        else
            # Find backup_switches upstream
            isolating["upstream"], rn["upstream"] = find_backup_switches(network,
                                                            rn["upstream"],
                                                            copy(seen),
                                                            switch_u)
            # Find backup_switches upstream
            isolating["downstream"], rn["downstream"] = find_backup_switches(network,
                                                              rn["downstream"],
                                                                seen,
                                                                switch_d)
        end
    end
    return rn, isolating
end

function find_backup_switches(network::RadialPowerGraph, 
        reconfigured_network::MetaGraph, seen::Vector{Int}, switches::Vector{Switch})
        reconfigured_b = copy(reconfigured_network)
        backup = Vector{Switch}()
        for switch in switches
            # Make sure that we don't traverse where we already have
            # traversed.
            visit = Vector{Int}()
            for v in [:src, :dst]
                append!(visit, all_neighbors(network.G, get_node_number(network.G, getfield(switch, v))))
            end
             find_isolating_switches!(network, reconfigured_b, backup,
                                      visit, seen)
        end
    return backup, reconfigured_b
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

