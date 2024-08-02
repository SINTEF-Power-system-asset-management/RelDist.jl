using RelDist: Network, NetworkPart, empty_network
using RelDist: Bus, NewBranch
using RelDist.battery: Battery, prepare_battery
using RelDist: t_supply, t_load, t_battery
using RelDist: segment_network

# Y-shaped network
network = empty_network()

network["bf_1"] = Bus("bf_1", t_supply, 2.0)
network["load_1"] = Bus("load_1", t_load, 1.0)
network["load_2"] = Bus("load_2", t_load, 1.0)

network["bf_2"] = Bus("bf_2", t_supply, 3.0)
network["load_3"] = Bus("load_3", t_load, 1.0)
network["load_4"] = Bus("load_4", t_load, 1.0)

network["battery"] = Bus("battery", t_battery, 1.0)

network["load_5"] = Bus("load_5", t_load, 2.0)

network["bf_1", "load_1"] = NewBranch()
network["load_1", "load_2"] = NewBranch()
network["load_2", "battery"] = NewBranch()

network["bf_2", "load_3"] = NewBranch()
network["load_3", "load_4"] = NewBranch()
network["load_4", "battery"] = NewBranch()

network["battery", "load_5"] = NewBranch()

batteries, _consumed_batteries = prepare_battery(network)
@testset "Test battery preparation" begin
    @test length(batteries) == 1
    @test batteries[1].rest_power["load_2"] == 0.0
    @test batteries[1].rest_power["load_4"] == 0.0
end

optimal_split = segment_network(network)
println(optimal_split)