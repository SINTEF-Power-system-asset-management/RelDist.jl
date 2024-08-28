module RelDist

# include("branch_types.jl")
# export Switch,
# get_minimum_switching_time,
# Branch,
# get_slack,
# slack_is_ref_bus,
# get_feeder_cap,
# are_edges_equal,
# edge2branch,
# create_slack_name

# include("relres.jl")
# export RelStruct, set_res!, ResFrames

include("corr_factors.jl")
export create_opal_year, get_corr_factor

include("relindices.jl")
export calculate_kile, set_rel_res!, f_lin, f_piece

include("relrad_io.jl")
export read_cost_functions, read_correction_factors_from_csv, read_loadprofile

# include("constants.jl")
# export MONTH_FACTORS,
# DAY_FACTORS,
# HOUR_FACTORS,
# COST_FUN,
# LOAD_PROFILES,
# TEMPERATURE_TABLE,
# TEMPERATURE_AVERAGE,
# REFERENCETIME_TABLE

# include("pref_calc.jl")
# export calculate_pref
#
# include("reconfiguration.jl")
# export calc_R, traverse

include("complete/mod.jl")
export empty_network, Network, Bus, BusKind, NetworkPart, segment_network

# include("relrad_calc.jl")
# export relrad_calc

end # module
