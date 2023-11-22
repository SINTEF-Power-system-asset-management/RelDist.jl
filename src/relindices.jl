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
function Base.in(number::Real, bound::Bound)::Bool
    return number < bound.upper && number >= bound.lower
end

"""Store a linear cost function"""
mutable struct Piece
    bound::Bound
    constant::Float64
    slope::Float64
    shift::Real
end

"""Evaluate a linear cost function."""
function f_lin(x::Piece, t::Real)::Float64
    return x.constant + x.slope*(t-x.shift)
end

"""Store a linear cost function"""
mutable struct PieceWiseCost
    pieces::Array{Piece, 1}
end

"""Evaluate a piecewise linear cost function."""
function f_piece(x::PieceWiseCost, t::Real)::Float64
    for piece in x.pieces
        if t in piece.bound
            return f_lin(piece, t)
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
function calculate_kile(p_ref::Real,
                        t::Real,
                        cost_function::PieceWiseCost,
                        corr::Real)
    return corr*p_ref*f_piece(cost_function, t)
end
function calculate_kile(interruption::Interruption,
                        cost_functions::Dict{String, PieceWiseCost},
                        corr_factors::CorrFactor)
    corr = get_corr_factor(corr_factors, interruption.start_time,
                           interruption.customer.consumer_type)
    duration = (interruption.end_time - interruption.start_time).value/3600000
    cost_function = cost_functions[interruption.customer.consumer_type]
    return corr*f_piece(cost_function, duration)*interruption.customer.p_ref
end

"""
    calculate_rel_indices calculates the unavailability and ENS.

    The equations are as follows:
    
    U = λ⋅t
    ENS = U⋅P
"""
function calculate_rel_indices(λ::Real, t::Real, P::Real)
    U = λ*t
    ENS = U*P
    
    return U, ENS
end

function set_rel_res!(res::RelStruct, λ::Real, t::Real, P::Real,
        cost_function::PieceWiseCost,
        l_pos::Integer, edge_pos::Integer)
    U, ENS = calculate_rel_indices(λ, t, P)

    IC = calculate_kile(P, t, cost_function, 1)
    # IC*λ gices CENS/year
    set_res!(res, λ, t, P, U, ENS, IC, IC*λ, l_pos, edge_pos)
end
