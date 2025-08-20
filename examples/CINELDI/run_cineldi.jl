include(joinpath(@__DIR__, "set_up_cineldi.jl"))
case.gen[[2, 3, 4], :Pmax] .= 2
network = Network(case)
t_orig = compress_relrad(network)
res = transform_relrad_data(network, t_orig, cost_functions)
ENS_total = sum(sum(eachcol(res.ENS[:, 1:end-1])))
CENS_total = sum(sum(eachcol(res.CENS[:, 1:end-1])))
U_orig = sum(sum(eachcol(res.U[:, 1:end-1])))

case.gen[[2, 3, 4], :Pmax] .= 3
network = Network(case)
t = compress_relrad(network)
res = transform_relrad_data(network, t, cost_functions)
ENS_total = sum(sum(eachcol(res.ENS[:, 1:end-1])))
CENS_total = sum(sum(eachcol(res.CENS[:, 1:end-1])))
U_total = sum(sum(eachcol(res.U[:, 1:end-1])))
