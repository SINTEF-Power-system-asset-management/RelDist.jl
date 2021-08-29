using RelRad

lastprofiler_filename = joinpath(@__DIR__, "../databases/lastprofiler.csv")
referencetime_filename =  joinpath(@__DIR__, "../databases/referansetidspunkt.json")
interruption_filename = joinpath(@__DIR__, "../databases/interruption_FASIT.json")
temperature_filename = joinpath(@__DIR__, "../databases/saetherengen.csv")

interruption = read_interruption(interruption_filename)
interruption_new = calculate_pref(lastprofiler_filename, referencetime_filename, temperature_filename,  interruption, -9.1)

epsilon = 0.5  # [kwh]
target_pref = 110.8732  # taken from FASIT report

@test (interruption_new.customer.p_ref - target_pref) < epsilon
