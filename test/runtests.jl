using Test
using RelRad

@testset "Testing IO" begin
    include("test_IO.jl")
end

@testset "Testing KILE calculation" begin
    include("test_kile_calc.jl")
end

@testset "Testing P_ref calculation" begin
    include("test_pref_calc.jl")
end

@testset "Testing Interruption costs calculation on basic radial net" begin
    include("test_relrad_calc.jl")
end

@testset "Testing Interruption costs calculation on fasad net" begin
	include("test_fasad_calc.jl")
end

@testset "Testing Interruption costs calculation on original fasad net" begin
	include("test_fasad_original_calc.jl")
end
