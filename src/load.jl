using SintPowerCase
using DataFrames
using Logging

mutable struct Load
    ID::String
    bus::String
    P::Real
    type::String
end

function Load(load::DataFrameRow)
    Load(load.ID, load.bus, load.P, load.type)
end

function get_loads(case::Case)
    if !isempty(case.load)
        if "P" ∈ names(case.load)
            return [Load(load) for load in eachrow(case.load)]
        else
            @warn "load dataframe found, but no load found, attemping to use bus dataframe"
            @warn "Assuming all loads to be residential"
            return [Load(load.ID,
                         load.bus,
                         case.bus[case.bus.ID .== load.bus, :Pd][1],
                         "residential") for load in eachrow(case.load)]
        end
    else
        @warn "no load dataframe found, using buses with Pd > 0 as loads."
        @warn "Assuming all loads to be residential"
        return [Load(string("D", bus.ID),
                     bus.ID,
                     bus.Pd) for bus in eachrow(case.bus) if bus.Pd>0]
    end
end

