using RelDist: Network, relrad_calc_2, compress_relrad
using RelDist: dot_plot, remove_switchless_branches
using RelDist: sort, edge_labels
using DataFrames: DataFrame, filter, names, select!, Not, select
using Test

network = Network(joinpath(@__DIR__, "../../examples/simplified_cineldi/cineldi_simple.toml"))

res = relrad_calc_2(network)
compres = compress_relrad(network)

sort!(res, :cut_edge)
sort!(compres, :cut_edge)

@test res[!, :cut_edge] == compres[!, :cut_edge]

res_names = sort!(names(res))
comp_names = sort!(names(compres))
@test res_names == comp_names

select!(res, res_names)
select!(compres, res_names)

function dataframes_approx_equal(df1::DataFrame, df2::DataFrame; kwargs...)
    @test size(df1) == size(df2)  # Check that both dataframes have the same dimensions

    for col in names(df1)
        @test all(isapprox.(df1[!, col], df2[!, col]; kwargs...))  # Check each column
    end
end

dataframes_approx_equal(select(res, Not(:cut_edge)), select(compres, Not(:cut_edge)))
