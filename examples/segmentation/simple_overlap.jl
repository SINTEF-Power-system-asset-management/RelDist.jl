include("setup.jl")

network = empty_network()

network["bf_6"] = Bus("bf_6", t_supply, 2.0)
network["bf_5"] = Bus("bf_5", t_supply, 2.0)

network["load_4"] = Bus("load_4", t_load, 1.0)
network["load_3"] = Bus("load_3", t_load, 1.0)
network["load_2"] = Bus("load_2", t_load, 1.0)
network["load_1"] = Bus("load_1", t_load, 1.0)

network["load_1", "load_2"] = NewBranch("load_1")
network["load_2", "load_3"] = NewBranch("load_2")
network["load_3", "load_4"] = NewBranch("load_3")

network["bf_5", "load_2"] = NewBranch("bf_5")
network["bf_6", "load_3"] = NewBranch("bf_6")

# Create a subtree for each supply, (call this a NetworkPart)
# The subtree needs to know how much more power it can supply
# For each leaf node in the subtree, 
# For each neighbour: 
# Recursively try the case where you add the neighbour to this part
# If there are no neighbours, return current state
# Evaluate by the total unused power. I suppose this needs to change to support more complex costs
supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
parts = [NetworkPart(network, supply) for supply in supplies]
# println(supplies)

# plot_that_graph(network, parts)
optimal_split = segment_network(network, parts)

# dot_plot(network; layout="neato")
dot_plot(network, optimal_split)

