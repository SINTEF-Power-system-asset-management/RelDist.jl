module RelDist

include("corr_factors.jl")
export create_opal_year, get_corr_factor

include("relindices.jl")
export calculate_kile, set_rel_res!, f_lin, f_piece

include("relrad_io.jl")
export read_cost_functions, read_correction_factors_from_csv, read_loadprofile

include("mod.jl")
export empty_network, Network, Bus, BusKind, NetworkPart, segment_network

end # module
