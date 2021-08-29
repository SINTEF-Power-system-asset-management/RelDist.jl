using TimeZones
using Query

@testset "Test reading of interruption data." begin
	interruption = read_interruption(joinpath(@__DIR__, "../databases/interruption.json"))
    @test interruption.start_time == ZonedDateTime(DateTime(2015, 10, 2, 0, 0), tz"Z")
    @test interruption.customer.consumer_type == "household"
    @test interruption.customer.p_ref == 0.8
    @test interruption.notified_interruption == false
end

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
        @select corr.household
        @collect
    end
    @test q1[1] == 0.6
end
