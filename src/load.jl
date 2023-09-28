using SintPowerCase
using DataFrames

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
        return [Load(load) for load in eachrow(case.load)]
    else
        return [Load(string("load_", bus.ID),
                     bus.ID,
                     bus.Pd) for bus in eachrow(case.bus)]
    end
end

