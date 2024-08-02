using Test

@testset "Trivial battery" include("trivial_battery_segment.jl")

@testset "Branching battery" include("branching_battery.jl")