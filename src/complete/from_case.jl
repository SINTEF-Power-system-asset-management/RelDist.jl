module from_case

using Graphs: SimpleGraph, Graph
import Graphs: connected_components
using MetaGraphsNext: MetaGraphsNext, label_for
import MetaGraphsNext: labels, edge_labels, neighbor_labels
import MetaGraphsNext: haskey, setindex!, getindex, delete!
using SintPowerCase: Case
using DataFrames: outerjoin, keys, Not, select
using DataStructures: DefaultDict, Queue

import Base

using ..network_graph:
    Network, empty_network, LoadUnit, SupplyUnit, KeyType, Bus, NewSwitch, NewBranch

function add_buses!(graphy::Network, case::Case)
    bus_withgen =
        outerjoin(case.bus, case.gen, on = :ID => :bus, renamecols = "_bus" => "_gen")
    buses_joined =
        outerjoin(bus_withgen, case.load, on = :ID => :bus, renamecols = "" => "_load")
    loads::Vector{LoadUnit} = []
    gens::Vector{SupplyUnit} = []
    prev_id::Union{KeyType,Nothing} = nothing

    for bus in eachrow(buses_joined)
        if bus[:ID] != prev_id && prev_id !== nothing
            graphy[prev_id] = Bus(loads, gens)
            loads = []
            gens = []
        end
        # If we dont use string key we need to parse the key
        prev_id = KeyType != String ? parse(KeyType, bus[:ID]) : bus[:ID]

        if bus[:P_load] !== missing
            loady =
                LoadUnit(bus[:ID_load], bus[:P_load], bus[:type_load], 1.0, bus[:nfc_load])
            push!(loads, loady)
        end
        if bus[:Pmax_gen] !== missing
            supplyy = SupplyUnit(bus[:ID_gen], bus[:Pmax_gen], !bus[:external_gen])
            push!(gens, supplyy)
        end
    end

    graphy[prev_id] = Bus(loads, gens)
end

function add_branches!(graphy::Network, case::Case)
    reldata = if :ID in propertynames(case.reldata)
        select(case.reldata, Not(:ID))
    else
        case.reldata
    end
    branch_joined = outerjoin(case.branch, reldata, on = [:f_bus, :t_bus])
    # Sort the branches such that (a->b) and (b->a) are immediately after each other
    permute!(
        branch_joined,
        sortperm([sort([row.f_bus, row.t_bus]) for row in eachrow(branch_joined)]),
    )

    for branch in eachrow(branch_joined)
        switches = []
        for switch in eachrow(case.switch)
            # (a->b) and (b->a) are the same branch
            if sort([branch[:f_bus], branch[:t_bus]]) !=
               sort([switch[:f_bus], switch[:t_bus]])
                continue
            end
            t_remote = if :t_remote in propertynames(switch)
                switch[:t_remote]
            else
                branch[:sectioning_time] # Cineldi compat
            end
            # If we dont use string key we need to parse the key
            f_bus = KeyType != String ? parse(KeyType, switch[:f_bus]) : switch[:f_bus]
            switchy = NewSwitch(f_bus, switch[:closed], t_remote)
            push!(switches, switchy)
        end

        repair_time = if :repair_time in propertynames(branch)
            branch[:repair_time]
        elseif :repairTime in propertynames(branch)
            branch[:repairTime] # simplified cineldi
        else
            branch[:r_perm] # Cineldi compat
        end

        permanent_fault_frequency = if :permanentFaultFrequency in propertynames(branch)
            branch[:permanentFaultFrequency]
        else
            branch[:lambda_perm] # Cineldi compat
        end

        branchy = NewBranch(repair_time, permanent_fault_frequency, switches)
        # If we dont use string key we need to parse the key
        f_bus = KeyType != String ? parse(KeyType, branch[:f_bus]) : branch[:f_bus]
        t_bus = KeyType != String ? parse(KeyType, branch[:t_bus]) : branch[:t_bus]
        graphy[f_bus, t_bus] = branchy
    end
end

Network(case_file::String) = Network(Case(case_file))
function Network(case::Case)
    graphy = empty_network()
    add_buses!(graphy, case)
    add_branches!(graphy, case)
    graphy
end

end
