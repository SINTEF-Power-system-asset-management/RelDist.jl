
interruption = read_interruption(joinpath(@__DIR__, "../databases/interruption.json"))
cost_functions = read_cost_functions(COST_FUN)

corr_factors = read_correction_factors_from_csv(MONTH_FACTORS,
                                                DAY_FACTORS,
                                                HOUR_FACTORS)
corr = 0.9*0.65 # manually read from tables

@test get_corr_factor(corr_factors,
                      interruption.start_time,
                      interruption.customer.consumer_type) == corr
# Household interrupted for 1.5 hours
cost = 8.8+14.7*1.5
@test calculate_kile(interruption,
                     cost_functions,
                     corr_factors) == corr*cost*0.8
