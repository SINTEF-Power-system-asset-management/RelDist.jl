using RelDist: Network, NetworkPart, dot_plot, to_dot, energy_not_served, is_supply, labels
using RelDist: remove_switchless_branches!, segment_network, relrad_calc_2, compress_relrad, transform_relrad_data
using RelDist: sort, edge_labels, isolate_and_get_time!, NewResult
using RelDist: read_cost_functions
using DataFrames: DataFrame, select, Not
using Accessors: @set
using FileIO
using CSV: CSV

cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")
cost_functions = read_cost_functions(cost_filename)

network = Network(joinpath(@__DIR__, "intern.toml"))

####################################
# Manually doing stuff for figures #
####################################
plot = dot_plot(network; layout="neato")
display(plot)
parts = [NetworkPart(network, vertex) for vertex in labels(network) if is_supply(network[vertex])]

compressed_network = deepcopy(network)
remove_switchless_branches!(compressed_network)
plot = dot_plot(compressed_network; layout="neato")
display(plot)
# FileIO.save("test.svg", plot) # This is how to write it to a file

#? Lets just do drawing of this one manually its less tedious
broken_network = deepcopy(compressed_network)
delete!(broken_network, "5")
optimal_split = segment_network(broken_network)

println(optimal_split)

##########
# Relrad #
##########
function print_relres(res::NewResult)
    lambda_df = select(res.lambda, Not(:cut_edge))
    lambda = sum(sum(eachcol(lambda_df)))

    outage_time_df = select(res.U, Not(:cut_edge))
    outage_time = sum(sum(eachcol(outage_time_df)))

    average_r = outage_time / lambda
    average_r_alt_df = select(res.t, Not(:cut_edge))
    average_r_alt = sum(sum(eachcol(average_r_alt_df .* lambda_df ./ sum(eachcol(lambda_df)))))
    println("$average_r == $average_r_alt")
    @assert average_r == average_r_alt

    ens_df = select(res.ENS, Not(:cut_edge))
    ENS = sum(sum(eachcol(ens_df)))

    kile_df = select(res.CENS, Not(:cut_edge))
    kile = sum(sum(eachcol(kile_df)))

    println("No per year: $lambda, outage_time: $outage_time, r: $average_r h/interr, ENS: $ENS, kile: $kile\n")
end

t = compress_relrad(network)
res::NewResult = transform_relrad_data(network, t, cost_functions)
print_relres(res)

no_renewable = deepcopy(network)
for node in labels(no_renewable)
    for supply_idx in 1:length(no_renewable[node].supplies)
        supply = no_renewable[node].supplies[supply_idx]
        if supply.is_battery
            no_renewable[node].supplies[supply_idx] = @set supply.power = 0
        end
    end
end
t = compress_relrad(no_renewable)
res::NewResult = transform_relrad_data(no_renewable, t, cost_functions)
print_relres(res)


###############################################
# Making a figure for each version of the net #
###############################################
if true == false
    Base.Filesystem.mkpath("tmp")
    for edge in edge_labels(network)
        broken_network = deepcopy(network)
        _ = isolate_and_get_time!(broken_network, edge)
        optimal_split = segment_network(broken_network)
        plot = dot_plot(broken_network, optimal_split)
        a, b = sort(edge)
        FileIO.save("tmp/$(a)-$(b).svg", plot)
    end

    plot = dot_plot(network)
    FileIO.save("tmp/full.svg", plot)

    t = relrad_calc_2(network)
    res = transform_relrad_data(network, t)
    CSV.write("tmp/t.csv", res.t)
    CSV.write("tmp/ens.csv", res.ENS)
    CSV.write("tmp/kile.csv", res.CENS)
end
