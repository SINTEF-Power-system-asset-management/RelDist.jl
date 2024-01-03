using SintPowerGraphs
using JLD2

network_filename = joinpath(@__DIR__, "../examples/reliability_course/excel_test.toml")
cost_filename = joinpath(@__DIR__, "../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)
network =  RadialPowerGraph(network_filename)

res, _, _ = relrad_calc(cost_functions, network)
IC = res["base"].CENS
ICt = res["temp"].CENS
IC_sum = sum(IC;dims=2)
ICt_sum = sum(ICt;dims=2)
println(IC_sum)
println(ICt_sum)


IC_sum_target = [265.75; 274.78; 227.7; 166.24]
@testset "Verifying unavailability" begin
U_target = 13.15
@test isapprox(sum(res["base"].U), U_target)
end

epsilon = 0.9
@test isapprox(sum(IC_sum), sum(IC_sum_target), atol=epsilon)

# Let us check if the code runs correctly when setting a specific time .
# Today is 2023-01-3, which is a Wednesday and it is 9ish.
# Let us read in the correction factors

date = DateTime(2023, 1, 3, 9)

corr_fac = read_correction_factors_from_csv(MONTH_FACTORS,
                                            DAY_FACTORS,
                                            HOUR_FACTORS)
agg_corr = get_corr_factor(corr_fac, date, "agriculture")
res_corr = get_corr_factor(corr_fac, date, "residential")

res, _, _ = relrad_calc(cost_functions, network, "2023-01-03T09")

IC_sum = sum(res["base"].CENS; dims=2)

IC_sum_target[1:2] = IC_sum_target[1:2]*res_corr
IC_sum_target[3:4] = IC_sum_target[3:4]*agg_corr
@test isapprox(sum(IC_sum), sum(IC_sum_target), atol=epsilon)
