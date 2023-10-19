using Configurations

@option "traverse" struct Traverse
    consider_cap::Bool = true
    only_feeder_cap::Bool = true
    method::String = "break_at_first"
end
