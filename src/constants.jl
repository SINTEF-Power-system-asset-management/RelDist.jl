const databases = joinpath(joinpath(@__DIR__, ".."), "databases")

const global DAY_FACTORS = joinpath(databases, "correction_factors_day.csv")
const global MONTH_FACTORS = joinpath(databases, "correction_factors_month.csv")
const global HOUR_FACTORS = joinpath(databases, "correction_factors_hour.csv")

const global COST_FUN = joinpath(databases, "cost_functions.json")

const global LOAD_PROFILES = joinpath(databases, "lastprofiler.csv")
const global TEMPERATURE_TABLE = joinpath(databases, "saetherengen.csv")
const global TEMPERATURE_AVERAGE = -9.1
const global REFERENCETIME_TABLE = joinpath(databases, "referansetidspunkt.json")
