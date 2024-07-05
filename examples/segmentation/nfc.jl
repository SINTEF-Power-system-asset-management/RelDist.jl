include("setup.jl")

function plot_nfc()
    network = empty_network()

    network["bf"] = Bus(t_supply, 2.0)

    network["nfc"] = Bus(t_nfc_load, 1.0)
    network["load"] = Bus(t_load, 2.0)


    network["bf", "nfc"] = NewBranch()
    network["nfc", "load"] = NewBranch()

    supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
    parts = Set([NetworkPart(network, supply) for supply in supplies])
    optimal_split = segment_network(network, parts)
    display(optimal_split)
    display(plot_that_graph(network, optimal_split))
end

plot_nfc()