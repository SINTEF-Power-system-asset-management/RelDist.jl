using TimeZones
using Query


@testset "Test reading of cost data." begin
    cost_functions = read_cost_functions(COST_FUN)
    @test cost_functions["agriculture"].pieces[1].constant == 5.6
end

@testset "Test reading of correction factors." begin
    corr_factors = read_correction_factors_from_csv(MONTH_FACTORS,
                                                    DAY_FACTORS,
                                                    HOUR_FACTORS)
    q1 = @from corr in corr_factors.month begin
        @where corr.month == "August"
        @select corr.residential
        @collect
    end
    @test q1[1] == 0.6
end
