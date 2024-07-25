using Graphs
using SintPowerCase
using SintPowerGraphs
using DataFrames

# This is just a simple script to test the method for handling overlap in
# reserve possibilities

network_filename = joinpath(@__DIR__, "cineldi_simple.toml")

case = Case(network_filename)
network = RadialPowerGraph(case)
g = network.G

# Create the two sets of vertices that can be fed by the two
#
bf1 = [g[string(v), :name] for v = 5:14]
bf2 = [g[string(v), :name] for v = 12:17]

overlapping = intersect(bf1, bf2)

for common in overlapping
    for n in all_neighbors(g, common)
        if (n ∉ bf1 || n ∉ bf2)
            if get_prop(g, Edge(n, common), :switch) == 1
                println(
                    string(g[n, :name], "-", g[common, :name], " crosses and has a switch"),
                )
            else
                println(
                    string(
                        g[n, :name],
                        "-",
                        g[common, :name],
                        " crosses and doesn't have a switch",
                    ),
                )
            end
        end
    end
end

