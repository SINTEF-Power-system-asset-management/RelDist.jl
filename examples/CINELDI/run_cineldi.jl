using RelDist
using SintPowerCase
using DataFrames
using DataFramesMeta

network_filename = joinpath(@__DIR__, "CINELDI.toml")
cost_filename = joinpath(@__DIR__, "../../databases/cost_functions.json")

cost_functions = read_cost_functions(cost_filename)

case = Case(network_filename)

# Remove the old/weird switches and add switches according to presentation
deleteat!(case.switch, 4:53)

# The reserve connections need breakers
push!(case.switch, deepcopy(case.switch[1, :]))
case.switch[1, :f_bus] = "36"
case.switch[1, :t_bus] = "35"
case.switch[1, :closed] = false
push!(case.switch, deepcopy(case.switch[1, :]))
case.switch[1, :f_bus] = "62"
case.switch[1, :t_bus] = "61"
case.switch[1, :closed] = false
push!(case.switch, deepcopy(case.switch[1, :]))
case.switch[1, :f_bus] = "88"
case.switch[1, :t_bus] = "87"
case.switch[1, :closed] = false
# Add switch data for the smart healing stuff
case.switch[!, :t_remote] .= 0.5 #1/3600 # I set the remote switching time to 1 second
case.switch[!, :t_manual] .= 0.5 # I set the manual switching time to 30 minutes
function add_switches(case::Case, switches::Vector{Tuple{String,String}}, closed::Bool)
    f_buses = [s[1] for s in switches]
    t_buses = [s[2] for s in switches]
    ns = length(f_buses)
    append!(
        case.switch,
        DataFrame(
            f_bus = f_buses,
            t_bus = t_buses,
            breaker = zeros(Bool, ns),
            closed = closed ? ones(Bool, ns) : zeros(Bool, ns),
            t_remote = 0.5 * ones(ns),
            t_manual = 0.5 * ones(ns),
        ),
    )
end

function add_smart_substation(case::Case, bus::String, switching_time::Real)
    bb = case.branch
    ss = case.switch
    # First check if the case has fault indicator and add if not.
    for ind in ["ind_f_bus", "ind_t_bus"]
        if ind ∉ names(bb)
            bb[!, Symbol(ind)] .= ""
        end
    end

    # Find all the branches going out of the smart substation
    branches = bb[bb.t_bus.==bus.||bb.f_bus.==bus, :]
    # Add fault indicators and switches to the smart substation
    for branch in eachrow(branches)
        if branch.f_bus == bus
            t_bus = branch.t_bus
        else
            t_bus = branch.f_bus
        end
        switch = ss[ss.f_bus.==bus.&&ss.t_bus.==t_bus, :]
        if isempty(switch)
            push!(ss, deepcopy(ss[1, :]))
            ss[1, :f_bus] = bus
            ss[1, :t_bus] = t_bus
            ss[1, :t_remote] = switching_time
        else
            ss[ss.f_bus.==bus.&&ss.t_bus.==t_bus, :t_remote] .= switching_time
        end
    end
    bb[bb.f_bus.==bus, :ind_f_bus] .= bus
    bb[bb.t_bus.==bus, :ind_t_bus] .= bus
end



# switches in the presentaiton
remote_switches = [
    ("26", "33"),
    ("33", "34"),
    ("33", "37"),
    ("46", "47"),
    ("47", "49"),
    ("47", "48"),
    ("85", "86"),
    ("86", "87"),
    ("86", "89"),
    ("86", "91"),
    ("86", "92"),
]

add_switches(case, remote_switches, true)

# Add additional switches

# switches = [("3", "4"), ("4", "6"), ("4", "5"),
#             ("5", "8"), ("5", "7"),
#             ("7", "10"), ("7", "11"), ("7", "9"),
#             ("9", "12"), ("9", "15"), ("9", "13"),
#             ("12", "16"), ("12", "26"),
#             ("26", "27"),
#             ("37", "38"), ("37", "40"),
#             ("40", "41"), ("40", "42"),
#             ("42", "43"), ("42", "109"), ("42", "44"),
#             ("44", "45"), ("45", "116"), ("45", "46"),
#             ("48", "63"), ("48", "67"),
#             ("70", "71"), ("71", "106"),
#             ("71", "72"), ("72", "107"), ("72", "73"),
#             ("75", "76"), ("76", "102"), ("76", "77"),
#             ("81", "82"), ("82", "100"), ("82", "83"),
#             ("83", "84"), ("83", "85"),
#             ("85", "97")]
switches = [#("3", "4"), ("4", "6"), ("4", "5"),
    #("5", "8"), ("5", "7"),
    #("7", "10"), ("7", "11"), 
    ("7", "9"),
    ("9", "12"),
    ("9", "15"),
    ("9", "13"),
    ("12", "16"),
    ("12", "26"),
    #("26", "27"),
    #("37", "38"), ("37", "40"),
    #("40", "41"), 
    ("40", "42"),
    ("42", "43"),
    ("42", "109"),
    ("42", "44"),
    ("44", "45"),
    ("45", "116"),
    ("45", "46"),
    #("48", "63"), ("48", "67"),
    ("70", "71"),
    ("71", "106"),
    ("71", "72"), #("72", "107"), ("72", "73"),
    ("75", "76"),
    ("76", "102"),
    ("76", "77"),
    #("81", "82"), ("82", "100"), ("82", "83"),
    #("83", "84"), ("83", "85"),
    #("85", "97")
]
add_switches(case, switches, true)



s = case.switch
for switch in remote_switches
    s[s.f_bus.==switch[1].&&s.t_bus.==switch[2], :t_remote] .= 1 / 3600
end

# #case.switch[!, :t_remote] .= 1/3600



#tune number and capacity of reserves  
#case.gen[[1,2,3,4], :external] .= true
case.gen[[2, 4], :Pmax] .= 0
case.gen[[3], :Pmax] .= 1

#tune load amount and type
#show(case.load, allrows=true) 

# use nfc loads at bus 10, 44 and 73
#case.load[case.load.bus.=="10", :nfc] .= true
#case.load[case.load.bus.=="44", :nfc] .= true
#case.load[case.load.bus.=="73", :nfc] .= true

case.load[:, :P] *= 0.7803748480170235

# Add a battery on bus 70

case.gen.E .= Inf
temp_gen = DataFrame(case.gen[end, :])
temp_gen.bus .= "9"
temp_gen.ID .= "B1"
temp_gen.external .= false
temp_gen.E .= 100
temp_gen.Pmax .= 2
case.gen = vcat(case.gen, temp_gen)


#add a second battery at bus 40
temp_gen2 = DataFrame(case.gen[end, :])
temp_gen2.bus .= "40"
temp_gen2.ID .= "B2"
temp_gen2.external .= false
temp_gen2.E .= 100
temp_gen2.Pmax .= 2
#case.gen = vcat(case.gen, temp_gen2)

add_smart_substation(case, "47", 1 / 3600)
add_smart_substation(case, "12", 1 / 3600)

network = Network(case)
t = compress_relrad(network)
res = transform_relrad_data(network, t, cost_functions)
ENS_total = sum(sum(eachcol(res.ENS[:, 1:end-1])))
CENS_total = sum(sum(eachcol(res.CENS[:, 1:end-1])))
U_total = sum(sum(eachcol(res.U[:, 1:end-1])))
println("U_total: $U_total")
println("ENS_total: $ENS_total")
println("CENS_total: $CENS_total")
