using SintPowerCase
using DataFrames
using Logging


mutable struct Load
    ID::String
    bus::String
    P::Real
    type::String
    corr::Real
    nfc::Bool
end

function Load(load::DataFrameRow, corr::Dict{String, <:Real})
    Load(load.ID, load.bus, load.P, load.type, corr[load.type], false)
end

function get_loads(case::Case, corr::Dict{String, <:Real})
    return [Load(load, corr) for load in eachrow(case.load)]
end

