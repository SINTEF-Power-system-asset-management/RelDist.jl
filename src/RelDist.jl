module RelDist

include("config.jl")
export Traverse, Failures, RelDistConf

include("load.jl")
export get_loads

include("branch_types.jl")
export Switch, get_minimum_switching_time, Branch, get_slack, slack_is_ref_bus, get_feeder_cap, are_edges_equal, edge2branch, create_slack_name

include("relres.jl")
export RelStruct, set_res!, ResFrames

include("relindices.jl")
export get_corr_factor, calculate_kile, set_rel_res!, f_lin, f_piece

include("relrad_io.jl")
export read_interruption, read_cost_functions, read_correction_factors_from_csv, read_loadprofile

include("constants.jl")
export MONTH_FACTORS, DAY_FACTORS, HOUR_FACTORS, COST_FUN, LOAD_PROFILES, TEMPERATURE_TABLE, TEMPERATURE_AVERAGE, REFERENCETIME_TABLE

include("pref_calc.jl")
export calculate_pref

include("relrad_calc.jl")
export relrad_calc

end # module
