using Configurations

@option "traverse" struct Traverse
    consider_cap::Bool = true
    only_feeder_cap::Bool = true
    method::String = "break_at_first"
end

@option "Failures" struct Failures
    switch_failures::Bool = false
    communication_failure::Bool = false
end

@option "Configuration for running RelDist.j" struct RelDistConf
    traverse::Traverse=Traverse()
    failures::Failures=Failures()
end
