include("setup.jl")

function test_simple_overlap()
    network = empty_network()

    network["bf_6"] = Bus(t_supply, 2.0)
    network["bf_5"] = Bus(t_supply, 2.0)

    network["load_4"] = Bus(t_load, 1.0)
    network["load_3"] = Bus(t_load, 1.0)
    network["load_2"] = Bus(t_load, 1.0)
    network["load_1"] = Bus(t_load, 1.0)

    network["load_1", "load_2"] = NewBranch()
    network["load_2", "load_3"] = NewBranch()
    network["load_3", "load_4"] = NewBranch()

    network["bf_5", "load_2"] = NewBranch()
    network["bf_6", "load_3"] = NewBranch()

    # Create a subtree for each supply, (call this a NetworkPart)
    # The subtree needs to know how much more power it can supply
    # For each leaf node in the subtree, 
    # For each neighbour: 
    # Recursively try the case where you add the neighbour to this part
    # If there are no neighbours, return current state
    # Evaluate by the total unused power. I suppose this needs to change to support more complex costs
    supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
    parts = Set([NetworkPart(network, supply) for supply in supplies])
    # println(supplies)

    # plot_that_graph(network, parts)
    optimal_split = segment_network(network, parts)
    display(optimal_split)
    display(plot_that_graph(network, optimal_split))
end

test_simple_overlap()