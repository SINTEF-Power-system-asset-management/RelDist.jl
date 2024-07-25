using RelDist: segment_network, empty_network, t_load, t_supply
using RelDist: kile_loss, NewBranch, PieceWiseCost, Bus
using MetaGraphsNext: labels, neighbor_labels
using Test

function test_kile_in_segmentation()
    network = empty_network()
    network["bf"] = Bus("bf", t_supply, 2.0)
    network["load_1"] = Bus("load_1", t_load, 1.0)
    network["load_2"] = Bus("load_2", t_load, 2.0)
    network["bf", "load_1"] = NewBranch()
    network["load_1", "load_2"] = NewBranch()

    loss_fn = kile_loss(network)
    optimal_split = segment_network(network, loss_fn)
    loss = loss_fn(optimal_split)
    display(optimal_split)
    @test loss == 4.0 * 2 + 1.0 * 0.5
end

test_kile_in_segmentation()