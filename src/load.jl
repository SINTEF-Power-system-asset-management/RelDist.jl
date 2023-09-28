using SintPowerCase
using DataFrames
using Logging

mutable struct Load
    ID::String
    bus::String
    P::Real
end

function Load(load::DataFrameRow)
    Load(load.ID, load.bus, load.P)
end

function get_loads(case::Case)
    if !isempty(case.load)
        if "P" ∈ names(case.load)
            return [Load(load) for load in eachrow(case.load)]
        else
            @warn "load dataframe found, but no load found, attemping to use bus dataframe"
            return [Load(load.ID,
                         load.bus,
                         case.bus[case.bus.ID .== load.bus, :Pd][1]) for load in eachrow(case.load)]
        end
    else
        @warn "no load dataframe found, using buses with Pd > 0 as loads."
        return [Load(string("D", bus.ID),
                     bus.ID,
                     bus.Pd) for bus in eachrow(case.bus) if bus.Pd>0]
    end
end

