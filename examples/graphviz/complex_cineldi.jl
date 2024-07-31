include("setup.jl")
using RelDist: delete!, get_start_guess, KeyType

network = Network(joinpath(@__DIR__, "../CINELDI/CINELDI.toml"))

for vertex in ["1"] # ["1", "62", "36", "88"] # remove all sources but 1
    delete!(network, vertex)
end

supplies = [vertex for vertex in labels(network) if is_supply(network[vertex])]
parts = [NetworkPart(network, supply) for supply in supplies]

# display(dot_plot(network, parts))

if true == false
    estimated_split = segment_network_classic(network, parts)
    display(dot_plot(network, estimated_split, "dot"))
end

if true == false # NB: NOT OPTIMAL
    # Backtracking to no overlap and doing complete search from there
    # This might work for some other net so i guess keep it, but it's too slow for this one
    estimated_split = segment_network_classic(network, parts)
    without_overlap = get_start_guess(network, estimated_split)
    display(dot_plot(network, without_overlap))

    optimal_split = segment_network(network, without_overlap)
    display(dot_plot(network, optimal_split))
end

if true == true
    # Removing all edges without switches to make it smaller
    compressed_network = deepcopy(network)
    remove_switchless_branches!(compressed_network)
    # display(dot_plot(compressed_network))

    if true == true
        # Do a complete search on the full network
        parts = [NetworkPart(network, supply) for supply in supplies]
        compressed_wo_trick = segment_network(compressed_network, deepcopy(parts))
        display(dot_plot(compressed_network, compressed_wo_trick))
    end

    if true == false # NB: NOT OPTIMAL
        # Do the backtracking trick on the compressed graph
        estimated_split = segment_network_classic(compressed_network, parts)
        without_overlap = get_start_guess(compressed_network, estimated_split)
        compressed_split = segment_network(compressed_network, without_overlap)

        display(dot_plot(compressed_network, compressed_split))
    end
end