using Dates
using TimeZones
import JSON
using CSV
using DataFrames

"""Parse the Zulu timeformat."""
function parse_zulu(zulu::String)::ZonedDateTime
    time_info = split(zulu, "Z")
    if size(time_info, 1) == 1
        @warn "Time zone not specified, I will assume Zulu time"
        return ZonedDateTime(DateTime(time_info), tz"Z")
    else
        return ZonedDateTime(DateTime(time_info[1]), tz"Z")
    end
end

function default_cost_functions()
    read_cost_functions(joinpath(@__DIR__, "../databases/cost_functions.json"))
end


function read_cost_functions(fname::String)::Dict{String,PieceWiseCost}
    io = open(fname)
    piecewise_cost = read_cost_functions(io)
    close(io)
    return piecewise_cost
end

function read_cost_functions(io::IOStream)::Dict{String,PieceWiseCost}
    json = JSON.parse(io)
    piecewise_cost = Dict{String,PieceWiseCost}()
    for (key, value) in json
        pieces = Array{Piece,1}(undef, 0)
        for (index, range) in enumerate(value["ranges"])
            if range[2] == "inf"
                range[2] = Inf
            end
            # If a time shit ( t-shift ) is defined use it otherwise set it to 0
            shift = "shift" in keys(value) ? value["shift"][index] : 0
            push!(
                pieces,
                Piece(
                    Bound(range[1], range[2]),
                    value["constants"][index],
                    value["slopes"][index],
                    shift,
                ),
            )
        end
        piecewise_cost[key] = PieceWiseCost(pieces)
    end
    return piecewise_cost
end

function read_correction_factors_from_csv(
    month::String,
    day::String,
    hour::String,
    decimal::Char = ',',
)::CorrFactor
    return CorrFactor(
        DataFrame(CSV.File(month, decimal = decimal)),
        DataFrame(CSV.File(day, decimal = decimal)),
        DataFrame(CSV.File(hour, decimal = decimal)),
    )
end

"""Read load profiles from file."""
function read_loadprofile(fname::String, lp_type::String)::DataFrame
    io = open(fname)
    lp = read_loadprofile(io, lp_type)
    close(io)
    return lp
end

"""Read load profiles from file stream."""
function read_loadprofile(io::IOStream, lp_type::String, decimal::Char = ',')::DataFrame
    lp = CSV.read(io, DataFrame, datarow = 3, decimal = decimal)
    return lp[(lp.Name.==lp_type), :]
end

""" Read reference time point from filename."""
function get_referencetime(fname::String, c_type::String)::Dict
    io = open(fname)
    json = JSON.parse(io)
    close(io)
    return json[c_type]
end



function parse_temperature(fname::String, decimal::Char = ',')::DataFrame
    csv = CSV.read(fname, DataFrame, decimal = decimal)
    T = csv[:, [:referenceTime, :value]]
    T[!, :referenceTime] = Date.(T[!, :referenceTime], "yyyy-mm-dd HH:MM:SSzzzz")
    return T
end
