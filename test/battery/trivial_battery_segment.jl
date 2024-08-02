using RelDist: Network, NetworkPart, empty_network
using RelDist: Bus, NewBranch
using RelDist.battery: Battery, prepare_battery
using RelDist: t_supply, t_load, t_battery
using RelDist: segment_network

network = empty_network()

network["bf"] = Bus("bf", t_supply, 1.0)

network["load_1"] = Bus("load_1", t_load, 1.0)
network["load_2"] = Bus("load_2", t_load, 1.0)
network["battery"] = Bus("battery", t_battery, 1.0)

network["bf", "load_1"] = NewBranch()
network["load_1", "load_2"] = NewBranch()
network["load_2", "battery"] = NewBranch()

batteries, _consumed_batteries = prepare_battery(network)
@testset "Test battery preparation" begin
    @test length(batteries) == 1
    @test batteries[1].rest_power["load_2"] == 0.0
end

optimal_split = segment_network(network)
println(optimal_split)
