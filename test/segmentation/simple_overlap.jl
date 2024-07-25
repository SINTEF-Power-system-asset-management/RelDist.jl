using RelDist: segment_network, empty_network, Bus, Network, NetworkPart, KeyType, t_load, t_nfc_load, t_supply
using RelDist: NewBranch
using MetaGraphsNext: labels, neighbor_labels
using Test

function test_simple_overlap()
    network = empty_network()

    network["bf_6"] = Bus("bf_6", t_supply, 2.0)
    network["bf_5"] = Bus("bf_5", t_supply, 2.0)

    network["load_4"] = Bus("load_4", t_load, 1.0)
    network["load_3"] = Bus("load_3", t_load, 1.0)
    network["load_2"] = Bus("load_2", t_load, 1.0)
    network["load_1"] = Bus("load_1", t_load, 1.0)

    network["load_1", "load_2"] = NewBranch()
    network["load_2", "load_3"] = NewBranch()
    network["load_3", "load_4"] = NewBranch()

    network["bf_5", "load_2"] = NewBranch()
    network["bf_6", "load_3"] = NewBranch()

    optimal_split = segment_network(network)
    for part in optimal_split
        if "load_3" in part.subtree
            @test "load_4" in part.subtree
        elseif "load_2" in part.subtree
            @test "load_1" in part.subtree
        end
    end
end

test_simple_overlap()