case_path = joinpath(@__DIR__, "cases") 

interruption = read_interruption(joinpath(case_path, "interruption.json"))
cost_functions = read_cost_functions(joinpath(case_path, COST_FUN))

corr_factors = read_correction_factors_from_csv(MONTH_FACTORS, DAY_FACTORS, HOUR_FACTORS)

kile = calculate_kile(interruption,
                     cost_functions,
                     corr_factors)

@show kile

