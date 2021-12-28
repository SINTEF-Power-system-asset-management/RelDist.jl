module RelDist

include("kile_calc.jl")
export get_corr_factor, calculate_kile

include("relrad_io.jl")
export read_interruption, read_cost_functions, read_correction_factors_from_csv, read_loadprofile

include("constants.jl")
export MONTH_FACTORS, DAY_FACTORS, HOUR_FACTORS, COST_FUN, LOAD_PROFILES, TEMPERATURE_TABLE, TEMPERATURE_AVERAGE, REFERENCETIME_TABLE

include("pref_calc.jl")
export calculate_pref

include("relrad_calc.jl")
export relrad_calc

end # module
