using LightXML
using DataFrames
import JSON
import CSV
using RelRad
using PowerGraphs
using LightGraphs
using MetaGraphs
using JLD2
using Statistics



function process_bkk_Case(network, dfs)
    mpc = Case()
    f_bkk_lines(mpc, network, dfs)
    f_bkk_switch(mpc, network, dfs)
    f_bkk_nodes(mpc, network, dfs)
    f_bkk_transformers(mpc, network, dfs)
    f_bkk_process_slack(mpc, dfs)
    return mpc
end

function f_bkk_lines(mpc, network, dfs)
    branches_columns = [
        "f_bus",
        "t_bus",
        "r",
        "x",
        "b",
        "rateA",
        "rateB",
        "rateC",
        "ratio",
        "angle",
        "name",
    ]
    reldata_columns = [
        "ID",
        "f_bus",
        "t_bus",
        "repairTime",
        "temporaryFaultFrequency",
        "permanentFaultFrequency",
        "sectioningTime",
        "temporaryFaultTime",
        "capacity",
    ]
    mpc.branch = DataFrame([Symbol(col) => Any[] for col in branches_columns])
    mpc.reldata = DataFrame([Symbol(col) => Any[] for col in reldata_columns])
    # generic assumptions about missing data?
    repair_time = 0.2 # hours
    temporaryFaultFrequency = 0.1
    permanentFaultFrequency = 0.1
    sectioningTime = 0 # Sectioning time is given in f_bkk_switch
    temporaryFaultTime = 0.02

    for row in collect(eachrow(network["lines"]))
        from = row["ConnectivityNode"]
        to = row["ConnectivityNode_1"]
        name = row["mRID"]
        lines_entry = [from, to, 0, 0, 0, 0, 0, 0, 0, 0, name]
        reldata_entry = [
            size(mpc.branch)[1] + 1,
            from,
            to,
            repair_time,
            temporaryFaultFrequency,
            permanentFaultFrequency,
            sectioningTime,
            temporaryFaultTime,
            row["value"],
        ] # to be checked
        push!(mpc.branch, lines_entry)
        push!(mpc.reldata, reldata_entry)
    end
end

function f_bkk_switch(mpc, network, dfs)
    switches_columns = ["f_bus", "t_bus", "breaker", "closed"]
    mpc.switch = DataFrame([Symbol(col) => Any[] for col in switches_columns])
    sectioningTime = 0.0 # to be checked
    for row in collect(eachrow(network["switches"]))
        mRID = row["mRID"]
        if mRID in dfs["Breaker"]["mRID"]
            breaker = "True"
        else
            breaker = "False"
        end
        from = row["ConnectivityNode"]
        to = row["ConnectivityNode_1"]
        switches_entry = [from, to, breaker, if row["normalOpen"] == 0
            "True"
        else
            "False"
        end]
        lines_entry = [from, to, 0, 0, 0, 0, 0, 0, 0, 0, mRID]
        reldata_entry = [size(mpc.branch)[1] + 1, from, to, 0, 0, 0, sectioningTime, 0, 0]
        push!(mpc.switch, switches_entry)
        push!(mpc.branch, lines_entry)
        push!(mpc.reldata, reldata_entry)
    end
end

function f_bkk_transformers(mpc, network, dfs)
    trafos_columns = ["ID", "f_bus", "t_bus", "rateA"]
    mpc.transformer = DataFrame([Symbol(col) => Any[] for col in trafos_columns])
    trafo_l = network["transformers"]["trafo_2w"]["l"]
    for row in collect(eachrow(network["transformers"]["trafo_2w"]["h"]))
        # if row["transformer_type"]=="secondary"
        transformer = row["PowerTransformer"]
        terminal =
            trafo_l[(trafo_l[:, :PowerTransformer].==transformer), :]["ConnectivityNode"][1]
        trafos_entry =
            [row["PowerTransformer"], row["ConnectivityNode"], terminal, row["ratedS"]]
        push!(mpc.transformer, trafos_entry)
        # else
        # I see that fasad does not explicitly declare the secondary bus of transformer as node, I add it manually
        #     push!(mpc_temp.nodes, [row["to"]])
        # end
        lines_entry =
            [row["ConnectivityNode"], terminal, 0, 0, 0, 0, 0, 0, 0, 0, transformer]
        reldata_entry = [
            size(mpc.branch)[1] + 1,
            row["ConnectivityNode"],
            terminal,
            0,
            0,
            0,
            0,
            0.02,
            row["ratedS"],
        ]
        push!(mpc.branch, lines_entry)
        push!(mpc.reldata, reldata_entry)
    end

    trafo_h = network["transformers"]["trafo_3w"]["h"]
    for row in collect(eachrow(network["transformers"]["trafo_3w"]["m"]))
        # if row["transformer_type"]=="secondary"
        transformer = row["PowerTransformer"]
        terminal =
            trafo_h[(trafo_h[:, :PowerTransformer].==transformer), :]["ConnectivityNode"][1]
        trafos_entry =
            [row["PowerTransformer"], terminal, row["ConnectivityNode"], row["ratedS"]]
        push!(mpc.transformer, trafos_entry)
        # else
        # I see that fasad does not explicitly declare the secondary bus of transformer as node, I add it manually
        #     push!(mpc_temp.nodes, [row["to"]])
        # end
        lines_entry =
            [row["ConnectivityNode"], terminal, 0, 0, 0, 0, 0, 0, 0, 0, transformer]
        reldata_entry = [
            size(mpc.branch)[1] + 1,
            row["ConnectivityNode"],
            terminal,
            0,
            0,
            0,
            0,
            0.02,
            row["ratedS"],
        ]
        push!(mpc.branch, lines_entry)
        push!(mpc.reldata, reldata_entry)
    end

    for row in collect(eachrow(network["transformers"]["trafo_3w"]["l"]))
        # if row["transformer_type"]=="secondary"
        transformer = row["PowerTransformer"]
        terminal =
            trafo_h[(trafo_h[:, :PowerTransformer].==transformer), :]["ConnectivityNode"][1]
        trafos_entry =
            [row["PowerTransformer"], terminal, row["ConnectivityNode"], row["ratedS"]]
        push!(mpc.transformer, trafos_entry)
        # else
        # I see that fasad does not explicitly declare the secondary bus of transformer as node, I add it manually
        #     push!(mpc_temp.nodes, [row["to"]])
        # end
        lines_entry =
            [row["ConnectivityNode"], terminal, 0, 0, 0, 0, 0, 0, 0, 0, transformer]
        reldata_entry = [
            size(mpc.branch)[1] + 1,
            row["ConnectivityNode"],
            terminal,
            0,
            0,
            0,
            0,
            0.02,
            row["ratedS"],
        ]
        push!(mpc.branch, lines_entry)
        push!(mpc.reldata, reldata_entry)

    end
end

function f_bkk_nodes(mpc, network, dfs)
    loads_columns = ["bus", "demand", "ref_demand"]
    nodes_columns = [
        "ID",
        "type",
        "Pd",
        "Qd",
        "Gs",
        "Bs",
        "area_num",
        "Vm",
        "Va",
        "baseKV",
        "zone",
        "max_Vm",
        "min_Vm",
    ]
    gen_columns = [
        "ID",
        "bus",
        "Pg",
        "Qg",
        "Gs",
        "Bs",
        "area_num",
        "Qmax",
        "Qmin",
        "Vg",
        "mBase",
        "status",
        "Pmax",
        "Pmin",
    ]
    mpc.loaddata = DataFrame([Symbol(col) => Any[] for col in loads_columns])
    mpc.bus = DataFrame([Symbol(col) => Any[] for col in nodes_columns])
    mpc.gen = DataFrame([Symbol(col) => Any[] for col in gen_columns])
    slack = 0
    Load_default = 0.4 # I cannot find info about loads (maybe declared in other networks?)
    for row in collect(eachrow(network["bus_idx"]))
        name = row["ConnectivityNode"]
        nodes_entry = [name, 1, 0, 0, 0, 0, 0, 1, 0, 22, 0, 1.2, 0.9]
        if name in network["loads"]["ConnectivityNode"]
            # df = mpc_temp.delivery_points[mpc_temp.delivery_points["name"] .== name,["demand", "reference_demand"]]
            nodes_entry[3] = Load_default #df["demand"][1]
            load_entry = [name, Load_default, Load_default] #[name, df["demand"][1], df["reference_demand"][1]]
            push!(mpc.loaddata, load_entry)
        end
        # # for the moment I omit generators
        # if slack == 0 && name in mpc.transformer[:f_bus] 
        #     slack = 1  
        #     nodes_entry[2] = 3
        # #     gen_entry = [size(mpc.gen)[1]+1, name, 0,0,0,0,1,0,1,0,0,0,0,0]
        # #     push!(mpc.gen, gen_entry)
        # end
        push!(mpc.bus, nodes_entry)
    end
end

function f_bkk_process_slack(mpc, dfs)
    mpc.transformer = leftjoin(
        mpc.transformer,
        dfs["ConnectivityNodeVoltage"],
        on = [(:f_bus, :ConnectivityNode)],
    )
    filtered_transformer =
        mpc.transformer[mpc.transformer.voltage.==maximum(mpc.transformer.voltage), :]
    slack = filtered_transformer[1, :bus_idx]
    mpc.bus[slack, :type] = 3
end

mutable struct networkXml
    dfs::Dict
    name::String
end

function read_xml_types(fname)
    io = open(fname)
    xml_types = JSON.parse(io)
    close(io)
    return xml_types
end

str2datatype = Dict("str" => String, "float64" => Float64, "bool" => Bool, "int64" => Int64)


function read_xmls(
    folder_name,
    xml_types_file = "databases/xml_types.json",
    drop_duplicates = true,
)
    xml_types = read_xml_types(xml_types_file)
    name = folder_name
    dfs = Dict()
    for key in collect(keys(xml_types))
        columns = ["mRID"]
        append!(columns, collect(keys(xml_types[key])))
        df_colnames = [Symbol(col) => Any[] for col in columns]
        df = DataFrame(df_colnames)
        push!(dfs, key => df)
    end

    for xml_file in readdir(folder_name)
        if !endswith(xml_file, ".xml")
            continue
        end
        tree = parse_file(join([folder_name, xml_file], "/"))
        tree_root = root(tree)
        _dfs = xml_to_dfs(tree_root)
        for key in keys(_dfs)
            dfs[key] = vcat(dfs[key], _dfs[key], cols = :union)
        end
    end
    set_column_types(dfs, xml_types)
    if drop_duplicates # Some objects may appear in multiple files
        for key in keys(dfs)
            try
                unique!(dfs[key])
            catch
                continue
            end
        end
    end
    return dfs, name # cls(dfs, name=folder_name.split('/')[-1])
end


function read_xml(filename, name = nothing, xml_types_file = "databases/xml_types.json")
    if name === nothing
        name = split(split(filename, '/')[end], '.')[1]
    end
    tree = parse_file(filename)
    tree_root = root(tree)
    xml_types = read_xml_types(xml_types_file)
    dfs = Dict()
    for key in collect(keys(xml_types))
        columns = ["mRID"]
        append!(columns, collect(keys(xml_types[key])))
        df_colnames = [Symbol(col) => Any[] for col in columns]
        df = DataFrame(df_colnames)
        push!(dfs, key => df)
    end
    _dfs = xml_to_dfs(tree_root)
    for key in keys(_dfs)
        dfs[key] = vcat(dfs[key], _dfs[key], cols = :union)
    end
    set_column_types(dfs, xml_types)
    return dfs, name
end


function set_column_types(dfs::Dict, xml_types::Dict)
    for key in keys(dfs)
        for name in names(dfs[key])
            if !(name in keys(xml_types[key]))
                #print(f'WARNING: missing column type: {table}.{column} (skipping)')
                continue
            end
            col_type = xml_types[key][name]
            try
                if col_type == "reference"
                    try
                        dfs[key][name] = String.(
                            reduce(hcat, split.(coalesce.(dfs[key][name], "_ "), '_'))
                        )[
                            end,
                            :,
                        ] # coalesce substitutes missing values with a default
                    catch
                        continue
                    end
                elseif col_type == "float64" || col_type == "int64"
                    try
                        dfs[key][name] =
                            parse.(
                                str2datatype[col_type],
                                replace.(dfs[key][name], ("," => ".")),
                            )
                    catch
                        continue
                    end
                elseif col_type == "bool"
                    dfs[key][name] =
                        convert(Array{str2datatype[col_type],1}, dfs[key][name] .== "true")
                else
                    try
                        dfs[key][name] = str2datatype[col_type].(dfs[key][name])
                    catch
                        continue
                    end
                end
            catch
                println(
                    "Failed to set type ({col_type}) of column ({column}) of DataFrame ({table})",
                )
            end
        end
    end
end

function xml_to_dfs(tree_root)
    dfs = Dict()
    for c in collect(child_elements(tree_root))
        df = rdf_props(c)
        if name(c) ∉ keys(dfs)
            dfs[name(c)] = DataFrame(df)
        else
            push!(dfs[name(c)], df, cols = :union)
        end
    end
    return dfs
end

function rdf_props(el)
    props = Dict()
    for sub_el in collect(child_elements(el))
        if name(sub_el) == "TransformerEnd.BaseVoltage"
            label = "endBaseVoltage"
        else
            label = split(name(sub_el), '.')[end]
        end
        try
            props[label] = collect(values(attributes_dict(sub_el)))[1]
        catch
            props[label] = content(sub_el)
        end
    end
    return props
end

function create_network_case(dfs, network_name)
    network = Dict{String,Any}("name" => network_name)
    bus_dict, bus_idx, reindex_to_pp_bus = add_buses(dfs)
    process_dfs(dfs, bus_idx)
    lines = add_lines(dfs, bus_idx)
    switches = add_switches(dfs)
    set_bus_voltages(dfs, reindex_to_pp_bus)
    transformers = add_transformers(dfs, bus_idx)
    loads = add_loads(dfs, bus_idx)

    push!(network, "bus_dict" => bus_dict)
    push!(network, "bus_idx" => bus_idx)
    push!(network, "lines" => lines)
    push!(network, "switches" => switches)
    push!(network, "transformers" => transformers)
    push!(network, "loads" => loads)

    return network
end

function terminalData(dfs)
    t1 = dfs["Terminal"][dfs["Terminal"][:sequenceNumber].==1, :]
    t2 = dfs["Terminal"][dfs["Terminal"][:sequenceNumber].==2, :]
    t3 = dfs["Terminal"][dfs["Terminal"][:sequenceNumber].==3, :]
    select!(
        t1,
        "ConductingEquipment" => "ConductingEquipment",
        "ConnectivityNode" => "ConnectivityNode1",
    )
    select!(
        t2,
        "ConductingEquipment" => "ConductingEquipment",
        "ConnectivityNode" => "ConnectivityNode2",
    )
    select!(
        t3,
        "ConductingEquipment" => "ConductingEquipment",
        "ConnectivityNode" => "ConnectivityNode3",
    )
    return leftjoin(
        leftjoin(t1, t2, on = "ConductingEquipment"),
        t3,
        on = "ConductingEquipment",
    )
end

function switch(dfs, bus_idx)
    from_bus, to_bus = terminals(dfs, bus_idx)
    switches = innerjoin(
        innerjoin(
            vcat(
                dfs["Breaker"],
                dfs["Disconnector"],
                dfs["Fuse"],
                dfs["GroundDisconnector"],
                dfs["Jumper"],
                dfs["LoadBreakSwitch"],
                cols = :union,
            ),
            from_bus,
            on = [(:mRID, :ConductingEquipment)],
            makeunique = true,
        ),
        to_bus,
        on = [(:mRID, :ConductingEquipment)],
        makeunique = true,
    )
    return switches
end


function equipmentContainerWithVoltage(dfs)
    bay = innerjoin(
        dfs["Bay"],
        select(
            dfs["VoltageLevel"],
            "mRID" => "VoltageLevel",
            "BaseVoltage" => "BaseVoltage",
            "Substation" => "Substation",
        ),
        on = "VoltageLevel",
    )
    voltage_level =
        leftjoin(dfs["VoltageLevel"], dfs["BaseVoltage"], on = :BaseVoltage => :mRID)
    result = vcat(bay, voltage_level, cols = :union)
    return result
end

function replace_missing(df::DataFrame, x::String, y::String)
    for row in eachrow(df)
        if ismissing(row[x])
            row[x] = row[y]
        end
    end
    return df
end

function replace_missing(df1::DataFrame, df2::DataFrame, x::String, y::String)
    for row in eachrow(df1)
        if ismissing(row[x])
            try
                row[x] = df2[df2[:, y].==row[y], x][1]
            catch e
                continue
            end
        end
    end
    return df1
end

function switchData(dfs)
    result = leftjoin(
        leftjoin(
            innerjoin(
                dfs["Switch"],
                dfs["TerminalData"],
                on = :mRID => :ConductingEquipment,
            ),
            select(dfs["BaseVoltage"], "mRID" => "mRID", "nominalVoltage" => "voltage"),
            on = :BaseVoltage => :mRID,
        ),
        select(
            dfs["EquipmentContainerWithVoltage"],
            "nominalVoltage" => "equipmentVoltage",
            "mRID" => "mRID",
        ),
        on = :EquipmentContainer => :mRID,
    )
    result = replace_missing(result, "voltage", "equipmentVoltage")
    return result
end

function process_dfs(dfs, bus_idx)
    dfs["Switch"] = switch(dfs, bus_idx)
    dfs["TerminalData"] = terminalData(dfs)
    dfs["EquipmentContainerWithVoltage"] = equipmentContainerWithVoltage(dfs)
    dfs["SwitchData"] = switchData(dfs)
    dfs["BusbarSectionData"] = busbarSectionData(dfs)
    dfs["ACLineSegmentData"] = acLineSegmentData(dfs)
    dfs["EnergyConsumerData"] = energyConsumerData(dfs)
    dfs["PowerTransformerEndData"] = powerTransformerEndData(dfs)
    dfs["ConductingEquipment"] = conductingEquipment(dfs)
    dfs["ConnectivityNodeVoltage"] = connectivityNodeVoltage(dfs)
end

function powerTransformerEndData(dfs)
    result = leftjoin(
        leftjoin(dfs["PowerTransformerEnd"], dfs["Terminal"], on = :Terminal => :mRID),
        select(dfs["BaseVoltage"], "mRID" => "mRID", "nominalVoltage" => "voltage"),
        on = :BaseVoltage => :mRID,
    )
    result.voltage = replace(result.voltage, 0.0 => missing)
    result = replace_missing(result, "voltage", "ratedU")
    return result
end

function conductingEquipment(dfs)
    result = vcat(
        select(dfs["SwitchData"], "mRID" => "mRID", "voltage" => "voltage"),
        select(dfs["BusbarSectionData"], "mRID" => "mRID", "voltage" => "voltage"),
        select(dfs["ACLineSegmentData"], "mRID" => "mRID", "voltage" => "voltage"),
        select(dfs["EnergyConsumerData"], "mRID" => "mRID", "voltage" => "voltage"),
        cols = :union,
    )
    result.voltage = replace(result.voltage, 0 => missing)
    return result
end

function busbarSectionData(dfs)
    result = leftjoin(
        leftjoin(
            innerjoin(
                dfs["BusbarSection"],
                dfs["TerminalData"],
                on = :mRID => :ConductingEquipment,
            ),
            select(dfs["BaseVoltage"], "mRID" => "mRID", "nominalVoltage" => "voltage"),
            on = :BaseVoltage => :mRID,
        ),
        select(
            dfs["EquipmentContainerWithVoltage"],
            "nominalVoltage" => "equipmentVoltage",
            "mRID" => "mRID",
        ),
        on = :EquipmentContainer => :mRID,
    )
    result = replace_missing(result, "voltage", "equipmentVoltage")
    # result[!,"voltage"] .= replace.(result.baseVoltage, missing => result["equipmentVoltage"])
    return result
end

function energyConsumerData(dfs)
    result = leftjoin(
        leftjoin(
            innerjoin(
                dfs["EnergyConsumer"],
                dfs["TerminalData"],
                on = :mRID => :ConductingEquipment,
            ),
            select(dfs["BaseVoltage"], "mRID" => "mRID", "nominalVoltage" => "voltage"),
            on = :BaseVoltage => :mRID,
        ),
        select(
            dfs["EquipmentContainerWithVoltage"],
            "nominalVoltage" => "equipmentVoltage",
            "mRID" => "mRID",
        ),
        on = :EquipmentContainer => :mRID,
    )
    # result.voltage .= replace.(result.baseVoltage, missing => result["equipmentVoltage"])
    result = replace_missing(result, "voltage", "equipmentVoltage")
    return result
end

function acLineSegmentData(dfs)
    result = leftjoin(
        leftjoin(
            leftjoin(
                innerjoin(
                    dfs["ACLineSegment"],
                    dfs["TerminalData"],
                    on = :mRID => :ConductingEquipment,
                ),
                select(dfs["PSRType"], "mRID" => "mRID", "name" => "PSRTypeName"),
                on = :PSRType => :mRID,
            ),
            select(dfs["BaseVoltage"], "mRID" => "mRID", "nominalVoltage" => "voltage"),
            on = :BaseVoltage => :mRID,
        ),
        select(
            dfs["EquipmentContainerWithVoltage"],
            "nominalVoltage" => "equipmentVoltage",
            "mRID" => "mRID",
        ),
        on = :EquipmentContainer => :mRID,
    )
    #result.voltage .= replace.(result.baseVoltage, missing => result["equipmentVoltage"])
    result = replace_missing(result, "voltage", "equipmentVoltage")
    return result
end

function connectivityNodeVoltage(dfs)
    grouped_result = groupby(
        leftjoin(
            select(dfs["Terminal"], Not(:sequenceNumber)),
            dfs["ConductingEquipment"],
            on = :ConductingEquipment => :mRID,
        ),
        :ConnectivityNode,
    )
    result = combine(grouped_result, (voltage = :voltage => median))
    result = replace_missing(
        result,
        dfs["PowerTransformerEndData"],
        "voltage",
        "ConnectivityNode",
    )
    grouped_result = groupby(result, :ConnectivityNode)
    result = combine(grouped_result, (voltage = :voltage => median))
    return result
end

function set_bus_voltages(dfs, reindex_to_pp_bus)

    dfs["ConnectivityNodeVoltage"] = reindex_to_pp_bus(dfs["ConnectivityNodeVoltage"])

    # Split the network into topological islands (we call this "group" below).
    # A requirement is that a single group of buses should share the same voltage.
    # nxgraph = pp.topology.create_nxgraph(net, respect_switches=False)
    # bus_with_group = pd.concat([
    #     pd.Series(index=buses, data=label, name='group')
    #     for label, buses in enumerate(pp.topology.connected_components(nxgraph)) 
    # ]).to_frame()

    # # voltage_source might give several answers to what the voltage should be for a 
    # # particular group. We take the median as a "democratic" way of picking the voltage.
    # group_with_voltage = bus_with_group\
    #     .merge(voltage_source, how='left', left_index=True, right_index=True)\
    #     .groupby('group').median()

    # Now that all the groups have been assigned a voltage, we distribute this to
    # the buses on the network. Some voltages might be nan at this point.
    # net.bus.vn_kv = bus_with_group.merge(group_with_voltage, how='left', left_on='group', right_index=True).voltage / 1000
end



function add_buses(dfs)
    buses = dfs["ConnectivityNode"]
    bus_dict = Dict()
    bus_idx = DataFrame([Symbol("ConnectivityNode") => Any[], Symbol("bus_idx") => Any[]])
    for row in collect(eachrow(buses))
        push!(bus_dict, row[1] => getfield(row, :row))
        push!(bus_idx, row[1] => getfield(row, :row))
    end
    function reindex_to_pp_bus(series_or_df)
        return innerjoin(bus_idx, series_or_df, on = :ConnectivityNode)
    end
    return bus_dict, bus_idx, reindex_to_pp_bus
end


function add_lines(dfs, bus_idx)
    from_bus, to_bus = terminals(dfs, bus_idx)
    lines = leftjoin(
        innerjoin(
            innerjoin(
                dfs["ACLineSegment"],
                from_bus,
                on = [(:mRID, :ConductingEquipment)],
                makeunique = true,
            ),
            to_bus,
            on = [(:mRID, :ConductingEquipment)],
            makeunique = true,
        ),
        dfs["PSRType"],
        on = [(:PSRType, :mRID)],
        makeunique = true,
    )
    return lines
end

function add_switches(dfs)
    return dfs["Switch"]
end

function add_transformers(dfs, bus_idx)
    lv_end_2w, hv_end_2w = trafo_2w_ends(dfs, bus_idx)
    lv_end_3w, mv_end_3w, hv_end_3w = trafo_3w_ends(dfs, bus_idx)
    transformers = Dict()
    transformers["trafo_2w"] = Dict("l" => lv_end_2w, "h" => hv_end_2w)
    transformers["trafo_3w"] = Dict("l" => lv_end_3w, "m" => mv_end_3w, "h" => hv_end_3w)
    return transformers
end

function trafo_2w_ends(dfs, bus_idx)
    power_transformer_end = leftjoin(
        leftjoin(
            dfs["PowerTransformerEnd"],
            select(dfs["Terminal"], [:mRID, :ConnectivityNode]),
            on = [(:Terminal, :mRID)],
        ),
        bus_idx,
        on = :ConnectivityNode,
    )
    trafo_end_groups = groupby(sort!(power_transformer_end, :ratedU), :PowerTransformer)
    trafo_end_count = combine(trafo_end_groups, nrow)
    trafo_2w = trafo_end_count[trafo_end_count[:nrow].==2, :][:PowerTransformer]
    i = 0
    lv_end_2w = DataFrame()
    hv_end_2w = DataFrame()
    for transformer in trafo_2w
        if i == 0
            lv_end_2w = DataFrame(trafo_end_groups[(PowerTransformer = transformer,)][1, :])
            hv_end_2w = DataFrame(trafo_end_groups[(PowerTransformer = transformer,)][2, :])
        else
            lv_end_2w = vcat(
                lv_end_2w,
                DataFrame(trafo_end_groups[(PowerTransformer = transformer,)][1, :]),
            )
            hv_end_2w = vcat(
                hv_end_2w,
                DataFrame(trafo_end_groups[(PowerTransformer = transformer,)][2, :]),
            )
        end
        i += 1
    end
    return lv_end_2w, hv_end_2w
end

function trafo_3w_ends(dfs, bus_idx)
    power_transformer_end = leftjoin(
        leftjoin(
            dfs["PowerTransformerEnd"],
            select(dfs["Terminal"], [:mRID, :ConnectivityNode]),
            on = [(:Terminal, :mRID)],
        ),
        bus_idx,
        on = :ConnectivityNode,
    )
    trafo_end_groups = groupby(sort!(power_transformer_end, :ratedU), :PowerTransformer)
    trafo_end_count = combine(trafo_end_groups, nrow)
    trafo_3w = trafo_end_count[trafo_end_count[:nrow].==3, :][:PowerTransformer]
    i = 0
    lv_end_3w = DataFrame()
    mv_end_3w = DataFrame()
    hv_end_3w = DataFrame()
    for transformer in trafo_3w
        if i == 0
            lv_end_3w = DataFrame(trafo_end_groups[(PowerTransformer = transformer,)][1, :])
            mv_end_3w = DataFrame(trafo_end_groups[(PowerTransformer = transformer,)][2, :])
            hv_end_3w = DataFrame(trafo_end_groups[(PowerTransformer = transformer,)][3, :])
        else
            lv_end_3w = vcat(
                lv_end_3w,
                DataFrame(trafo_end_groups[(PowerTransformer = transformer,)][1, :]),
            )
            mv_end_3w = vcat(
                mv_end_3w,
                DataFrame(trafo_end_groups[(PowerTransformer = transformer,)][2, :]),
            )
            hv_end_3w = vcat(
                hv_end_3w,
                DataFrame(trafo_end_groups[(PowerTransformer = transformer,)][3, :]),
            )
        end
        i += 1
    end
    return lv_end_3w, mv_end_3w, hv_end_3w
end

function terminals(dfs, bus_idx)
    terminal_1 = dfs["Terminal"][dfs["Terminal"][:sequenceNumber].==1, :]
    terminal_2 = dfs["Terminal"][dfs["Terminal"][:sequenceNumber].==2, :]
    from_bus = leftjoin(terminal_1, bus_idx, on = :ConnectivityNode)
    to_bus = leftjoin(terminal_2, bus_idx, on = :ConnectivityNode)
    return rename(from_bus, :bus_idx => :from_bus), rename(to_bus, :bus_idx => :to_bus)
end

function add_loads(dfs, bus_idx)
    from_bus, to_bus = terminals(dfs, bus_idx)
    loads = innerjoin(
        dfs["BusbarSection"],
        from_bus,
        on = [(:mRID, :ConductingEquipment)],
        makeunique = true,
    )
    return loads
end


function export_buses(network)
    df = DataFrame(
        ID = Int[],
        type = Int[],
        Pd = Float64[],
        Qd = Float64[],
        Gs = Float64[],
        Bs = Float64[],
        area_num = Int[],
        Vm = Float64[],
        Va = Float64[],
        baseKV = Float64[],
        zone = Int,
        max_Vm = Float64[],
        min_Vm = Float64[],
    )
    rw = Array{Any,1}()
    for bus in network["bus_idx"][2]

    end

end

# filename = "examples/bkk/P_10273816_C_9804904.xml"
filename = "examples/CIM_eksport_Unscrambled/XML/NS_10275717_C_10812033.xml"
xml_types_file = "databases/xml_types.json"
folder_name = "examples/CIM_eksport_Unscrambled/XML"

interruption_filename = "./examples/cases/interruption_FASIT.json"
cost_filename = "./examples/excel_ex/cost_functions.json"

interruption = read_interruption(interruption_filename)
cost_functions = read_cost_functions(cost_filename)


println("Starting importing xmls...")
#dfs, network_name = read_xmls(folder_name)
dfs, network_name = read_xml(filename)
println("Finished importing xml.")
# @load "dfs_netname.jld2" dfs network_name

println("Converting xml data in RELRAD format")
network = create_network_case(dfs, network_name)
# folder = "examples/exported_network"

mpc = process_bkk_Case(network, dfs)
println("Finished xml to RELRAD conversion")

println("Building graph from RELRAD format")
G, ref_bus = read_case(mpc)

filtered_branches = CSV.File("databases/bkk_islanding_filter.csv") |> DataFrame

meta, meta_radial = graphMap(mpc, G, ref_bus, filtered_branches)
meta_network = MetaPowerGraph(G, mpc, ref_bus, meta, meta_radial)
println("Finished building graph from RELRAD format")

# @save "workspace.jld2" meta_network
println("Starting RELRAD calculation")
IC, ICt, L, edge_pos =
    relrad_calc(interruption, cost_functions, meta_network, filtered_branches)
println("Finished RELRAD calculation")

@save "IC.jld2" IC
@save "L.jld2" L
@save "edge_pos.jld2" edge_pos

println("Printing results")
IC_sum = sum(IC; dims = 2)
ICt_sum = sum(ICt; dims = 2)
println(IC_sum)
println(ICt_sum)
println("Finished printing results")

println(network_name)
