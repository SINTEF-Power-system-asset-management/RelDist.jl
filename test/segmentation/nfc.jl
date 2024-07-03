using RelDist: segment_network, empty_network, t_load, t_nfc_load, t_supply
using RelDist: Bus, NewBranch, NetworkPart
using MetaGraphsNext: labels, neighbor_labels
using Test

function test_load_dropping()
    network = empty_network()

    network["bf"] = Bus(t_supply, 2.0)

    network["nfc"] = Bus(t_nfc_load, 1.0)
    network["load"] = Bus(t_load, 2.0)


    network["bf", "nfc"] = NewBranch()
    network["nfc", "load"] = NewBranch()


    optimal_split = segment_network(network)
    for part::NetworkPart in optimal_split
        if "load" in part.subtree
            @test "nfc" in part.subtree
        end
    end
end

test_load_dropping()