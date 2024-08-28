using Dates

"""Struct for correction factors."""
mutable struct CorrFactor
    month::DataFrame
    day::DataFrame
    hour::DataFrame
end


"""Get correcition factor for cost function"""
function get_corr_factor(corr_factor::CorrFactor, date::DateTime, c_group::String)::Float64
    m = corr_factor.month[month(date), Symbol(c_group)]
    d = corr_factor.day[dayofweek(date), Symbol(c_group)]
    h = first(filter(row -> hour(date) <= row.hour, corr_factor.hour))[Symbol(c_group)]
    return m * d * h
end

"""
    Create OPAL year.

    The OPAl year is a year with one week in each month,
    and each week starts with a Monday. This results in
    a year with 2016 hours, and is the format used for the
    KILE correction factors.
"""
function create_opal_year()
    hcat(
        ceil.(Int, (1:12*7*24) / 7 / 24), # month vector
        repeat(ceil.(Int, (1:24*7) / 24), outer = 12), # day vector
        repeat(ceil.(Int, (1:24)), outer = 7 * 12),
    ) # hour vector
end
