traverse = Traverse()
failures = Failures()
conf = RelDistConf()

@test traverse.consider_cap == true
@test traverse.only_feeder_cap == true

@test failures.switch_failure_prob == 0.0
@test failures.communication_failure_prob == 0.0

@test conf.traverse.consider_cap
