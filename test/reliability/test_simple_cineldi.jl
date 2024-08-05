using RelDist: Network, relrad_calc_2, read_cost_functions, transform_relrad_data
using RelDist: branches
using Accessors
using DataFrames
using Test

network_filename = joinpath(@__DIR__, "../../examples/simplified_cineldi/cineldi_simple.toml")
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)
network = Network(network_filename)

# Just to make it a bit simpler to compare
for branch in branches(network)
    for switch_idx in 1:length(branch.switches)
        switch = branch.switches[switch_idx]
        branch.switches[switch_idx] = @set switch.switching_time = 0.5
    end
end

outage_times = relrad_calc_2(network)
res = transform_relrad_data(network, outage_times, cost_functions)

res.t

# Case 1 in the power point
let row = filter(row -> row[:cut_edge] === ("15", "16"), res.U)
    @test isapprox(sum(row[1, 1:end-1]), 0.418, atol=0.01)
end

# Case 2 in the power point. NOT! BF2 can aslo supply
# load 10. This is therefore not case 2. Check what the
# correct answer should be for this case.
let row = filter(row -> row[:cut_edge] === ("2", "3"), res.U)
    @test isapprox(sum(row[1, 1:end-1]), 0.333, atol=0.01)
end

# If we increase the power of the load at bus 10, we get
# case 2.
# get the same result as before.
let bus = network["10"]
    network["10"] = @set bus.loads[1].power = 2.0
end

outage_times = relrad_calc_2(network)
res = transform_relrad_data(network, outage_times, cost_functions)

let row = filter(row -> row[:cut_edge] === ("2", "3"), res.U)
    @test isapprox(sum(row[1, 1:end-1]), 0.333, atol=0.01)
end

# # If we delete the switch between 12 and 14 we should also get
# # the same result as before.
let bus = network["10"]
    network["10"] = @set bus.loads[1].power = 2.0
end
let branch = network["12", "14"]
    network["12", "14"] = @set branch.switches = []
end

outage_times = relrad_calc_2(network)
res = transform_relrad_data(network, outage_times, cost_functions)

let row = filter(row -> row[:cut_edge] === ("2", "3"), res.U)
    @test isapprox(sum(row[1, 1:end-1]), 0.333, atol=0.01)
end

# TODO: Port the rest of the tests
