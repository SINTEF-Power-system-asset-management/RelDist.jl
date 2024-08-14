using RelDist: Network, NetworkPart, t_supply, t_load, NewBranch
using Test

function test_all_loads_supplied()
    network = empty_network()
    network["MF"] = Bus("MF", t_supply, 2.0)

    network["load_2"] = Bus("load_2", t_load, 1.0)
    network["load_1"] = Bus("load_1", t_load, 1.0)

    network["MF", "load_1"] = NewBranch()
    network["load_1", "load_2"] = NewBranch()

    optimal_split = segment_network(network)

    for part in optimal_split
        @test all_loads_supplied(network, part)
    end
end

test_all_loads_supplied()
