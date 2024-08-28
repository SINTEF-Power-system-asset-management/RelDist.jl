"""
NFC are loads that have no cost of disconnecting. This really means we just skip them,
but by changing the cost function we can choose to take them into account. By default
we use them as a tie-breaker, such that if two states are equal otherwise we include the
NFC load in the networkpart (without reducing the rest power)

NFC is short for Non-Firm Connection (norsk: tilknytting med vilkår)
"""

using RelDist: segment_network, empty_network, t_load, t_nfc_load, t_supply
using RelDist: Bus, NewBranch, NetworkPart
using MetaGraphsNext: labels, neighbor_labels
using Test

function test_load_dropping()
    network = empty_network()

    network["bf"] = Bus("bf", t_supply, 2.0)

    network["nfc"] = Bus("nfc", t_nfc_load, 1.0)
    network["load"] = Bus("load", t_load, 2.0)


    network["bf", "nfc"] = NewBranch()
    network["nfc", "load"] = NewBranch()


    optimal_split = segment_network(network)
    for part::NetworkPart in optimal_split
        if "load" in part.subtree
            @test "nfc" in part.subtree
        end
    end
    @test length(optimal_split) == 1
end

test_load_dropping()
