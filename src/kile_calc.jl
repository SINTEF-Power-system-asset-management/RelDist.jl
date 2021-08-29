using TimeZones
using DataFrames

"""Store information about a customer."""
mutable struct Customer
    consumer_type::String
    loadprofile_type::String
    annual_consumption::Float64
    p_ref::Float64
end

"""Store information about an interruption"""
mutable struct Interruption
    start_time::ZonedDateTime
    end_time::ZonedDateTime
    customer::Customer
    notified_interruption::Bool
end

"""Store upper and lower bounds for piecewise cost functions"""
mutable struct Bound
    lower::Float64
    upper::Float64
end

"""Check if a float is within a bound"""
function Base.in(number::Float64, bound::Bound)::Bool
    return number < bound.upper && number >= bound.lower
end

"""Store a linear cost function"""
mutable struct Piece
    bound::Bound
    constant::Float64
    slope::Float64
end

"""Evaluate a linear cost function."""
function f(x::Piece, t::Float64)::Float64
    return x.constant + x.slope*t
end

"""Store a linear cost function"""
mutable struct PieceWiseCost
    pieces::Array{Piece, 1}
end

"""Evaluate a piecewise linear cost function."""
function f(x::PieceWiseCost, t::Float64)::Float64
    for piece in x.pieces
        if t in piece.bound
            return f(piece, t)
        end
    end
end

"""Struct for correction factors."""
mutable struct CorrFactor
    month::DataFrame
    day::DataFrame
    hour::DataFrame
end

"""Get correcition factor for cost function"""
function get_corr_factor(corr_factor::CorrFactor,
                         date::ZonedDateTime, c_group::String)::Float64
    m = corr_factor.month[month(date), Symbol(c_group)]
    d = corr_factor.day[dayofweek(date), Symbol(c_group)]
    h = first(filter(row-> hour(date) <= row.hour,
                    corr_factor.hour))[Symbol(c_group)]
    return m*d*h
end

"""Calculates the KILE"""
function calculate_kile(interruption::Interruption,
                        cost_functions::Dict{String, PieceWiseCost},
                        corr_factors::CorrFactor)
    corr = get_corr_factor(corr_factors, interruption.start_time,
                           interruption.customer.consumer_type)
    duration = (interruption.end_time - interruption.start_time).value/3600000
    cost_function = cost_functions[interruption.customer.consumer_type]
    return corr*f(cost_function, duration)*interruption.customer.p_ref
end

function calculate_kile(interruption::Interruption,
                        cost_functions::Dict{String, PieceWiseCost},
                        failure_rate::Float64,
                        p_ref::Float64,
                        t::Float64
                        )
    corr = 1  # considering the failure occurring at reference time
    duration = t
    cost_function = cost_functions[interruption.customer.consumer_type]
    return corr*failure_rate*f(cost_function, duration)*p_ref
end
