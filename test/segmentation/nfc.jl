using RelDist: segment_network, empty_network, Bus, Network, NetworkPart, KeyType, t_load, t_nfc_load, t_supply
using MetaGraphsNext: labels, neighbor_labels
using Test

function test_load_dropping()
    network = empty_network()

    network["bf"] = Bus(t_supply, 2.0)

    network["nfc"] = Bus(t_nfc_load, 1.0)
    network["load"] = Bus(t_load, 2.0)


    network["bf", "nfc"] = nothing
    network["nfc", "load"] = nothing


    optimal_split = segment_network(network)
    for part::NetworkPart in optimal_split
        if "load" in part.subtree
            @test "nfc" in part.subtree
            @test "nfc" in part.dropped_loads
        end
    end
end

test_load_dropping()