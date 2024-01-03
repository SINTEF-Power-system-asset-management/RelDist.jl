using RelDist
using Test

@testset "Testing IO" begin
    include("test_IO.jl")
end

@testset "Testing branch types" begin
    include("test_branch_types.jl")
end

@testset "Testing configuration structs" begin
    include("test_configurations.jl")
end

# This is using the interruptionn format that we have not used
# for years.
# @testset "Testing KILE calculation" begin
    # include("test_kile_calc.jl")
# end

# @testset "Testing P_ref calculation" begin
    # include("test_pref_calc.jl")
# end

@testset "Testing Interruption costs calculation on basic radial net" begin
    include("test_relrad_calc_CINELDI.jl")
end

@testset "Testing Interruption costs calculation on fasad net" begin
    include("test_fasad_calc_CINELDI.jl")
end
