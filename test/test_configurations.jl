traverse = Traverse()
failures = Failures()
conf = RelDistConf()

@test traverse.consider_cap == true
@test traverse.only_feeder_cap == true

@test failures.switch_failures == false
@test failures.communication_failure == false

@test conf.traverse.consider_cap == true
