module RelDist

include("corr_factors.jl")
export create_opal_year, get_corr_factor

include("relindices.jl")
export calculate_kile, set_rel_res!, f_lin, f_piece

include("relrad_io.jl")
export read_cost_functions,
    read_correction_factors_from_csv, read_loadprofile, default_cost_functions

include("mod.jl")
export empty_network, Network, Bus, BusKind, NetworkPart, segment_network

include("reldist.jl")
export compress_relrad, transform_relrad_data, relrad_calc_2, isolate_and_get_time!
export relrad_calc_multiple_os, power_matrix

end # module
