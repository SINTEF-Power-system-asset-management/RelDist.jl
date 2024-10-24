using Test
network_filename = joinpath(@__DIR__, "../examples/simplified_cineldi/cineldi_simple.toml")
cost_filename = joinpath(@__DIR__, "../databases/cost_functions.json")

network = Network(network_filename)

dfs_edges_res = [
    ("1", "2"),
    ("2", "3"),
    ("3", "5"),
    ("5", "8"),
    ("8", "9"),
    ("9", "12"),
    ("12", "14"),
    ("14", "15"),
    ("15", "16"),
    ("16", "17"),
    ("12", "13"),
    ("9", "10"),
    ("10", "11"),
    ("5", "6"),
    ("6", "7"),
    ("3", "4"),
]
@test dfs_edges(network, "1") == dfs_edges_res

@test find_edge(network, ("3", "5"), "8", "9")
@test find_edge(network, ("3", "5"), "9", "8") == false
