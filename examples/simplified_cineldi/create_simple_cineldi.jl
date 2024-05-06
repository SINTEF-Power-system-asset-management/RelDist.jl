using SintPowerCase
using DataFrames
using DataFramesMeta

case_filename = joinpath(@__DIR__, "../CINELDI/CINELDI.toml")

case = Case(case_filename)

branch = case.branch
reldata = case.reldata
switch = case.switch
bus = case.bus

# Reorder the buses to make it a bit easer
bus.ID = parse.(Int, bus.ID)
sort!(bus, :ID)
bus.ID = string.(bus.ID)

branch_new = DataFrame(case.branch[1:15, :])
reldata_new = DataFrame(case.reldata[1:15, :])
switch_new = DataFrame(case.switch[1:15, :])
bus_new = DataFrame(bus[1:16, :])
gen_new = DataFrame(case.gen[1:3, :])
gen_new[2, :bus] = "10"
gen_new[3, :bus] = "16"


# Make the loads
# I will scale the later.
load_new = DataFrame(case.load[1:9, :])
load_new.ID = [string("L", i) for i in 1:9]
load_new.bus = ["2", "4", "6", "7", "9", "12", "13", "14", "15"]

loaddata_new = DataFrame(case.loaddata[1:9, :])
loaddata_new.bus = load_new.bus
loaddata_new.ID = load_new.ID
loaddata_new.P = load_new.P


function merge_branches(df, branches)
    # Adding lines together like this is technically not correct,
    # but it is good enough for this purpose.
    @combine(df[branches, :], $AsTable =
             (br_r=sum(:br_r), br_x=sum(:br_x),
              br_b=sum(:br_b), rateA=findmin(:rateA)[1]))[1, :]
end

function merge_reldata(df, branches)
         @combine(df[branches, :], $AsTable =
             (lambda_perm=sum(:lambda_perm), lambda_temp=sum(:lambda_temp),
              r_perm=findmax(:r_perm)[1], r_temp=findmax(:r_temp)[1]))[1, :]
end

π_line = [:br_r, :br_x, :br_b, :rateA]
rel_line = [:lambda_perm, :lambda_temp, :r_perm, :r_temp]

# Make line 2
branch_new[2, π_line] = merge_branches(branch, 2:4)
reldata_new[2, rel_line] = merge_reldata(reldata, 2:4)
switch_new[3, :] = switch[4, :]

# Make line 3
branch_new[3, π_line] = get_branch(case, "4", "6")[1, π_line]
reldata_new[3, rel_line] = get_branch_data(case, :reldata, "4", "6")[1, rel_line]
switch_new[4, :f_bus] = "3"
switch_new[4, :t_bus] = "4"

# Make line 4
branch_new[4, :f_bus] = "3"
branch_new[4, :t_bus] = "5"
reldata_new[4, :f_bus] = "3"
reldata_new[4, :t_bus] = "5"
branch_new[4, π_line] = merge_branches(branch, 4:7)
reldata_new[4, rel_line] = merge_reldata(reldata, 4:7)
switch_new[5, :f_bus] = "3"
switch_new[5, :t_bus] = "5"

# Make line 5
branch_new[5, :f_bus] = "5"
branch_new[5, :t_bus] = "6"
reldata_new[5, :f_bus] = "5"
reldata_new[5, :t_bus] = "6"
branch_new[5, π_line] = get_branch(case, "12", "16")[1, π_line]
reldata_new[5, rel_line] = get_branch_data(case, :reldata, "12", "16")[1, rel_line]
switch_new[6, :f_bus] = "5"
switch_new[6, :t_bus] = "6"

# Make line 6
branch_new[6, :f_bus] = "6"
branch_new[6, :t_bus] = "7"
reldata_new[6, :f_bus] = "6"
reldata_new[6, :t_bus] = "7"
branch_new[6, π_line] = merge_branches(branch, 49:55)
reldata_new[6, rel_line] = merge_reldata(reldata, 49:55)

# Make line 7
branch_new[7, :f_bus] = "5"
branch_new[7, :t_bus] = "8"
reldata_new[7, :f_bus] = "5"
reldata_new[7, :t_bus] = "8"
branch_new[7, π_line] = get_branch(case, "26", "33")[1, π_line]
reldata_new[7, rel_line] = get_branch_data(case, :reldata, "26", "33")[1, rel_line]
switch_new[7, :f_bus] = "5"
switch_new[7, :t_bus] = "8"

# Make line 8
branch_new[8, :f_bus] = "8"
branch_new[8, :t_bus] = "9"
reldata_new[8, :f_bus] = "8"
reldata_new[8, :t_bus] = "9"
branch_new[8, π_line] = get_branch(case, "33", "34")[1, π_line]
reldata_new[8, rel_line] = get_branch_data(case, :reldata, "33", "34")[1, rel_line]
switch_new[8, :f_bus] = "8"
switch_new[8, :t_bus] = "9"

# Make line 9
branch_new[9, :f_bus] = "9"
branch_new[9, :t_bus] = "10"
reldata_new[9, :f_bus] = "9"
reldata_new[9, :t_bus] = "10"
branch_new[9, π_line] = merge_branches(branch, 65:66)
reldata_new[9, rel_line] = merge_reldata(reldata, 65:66)
switch_new[9, :f_bus] = "9"
switch_new[9, :t_bus] = "10"
switch_new[9, :closed] = false
switch_new[10, :f_bus] = "9"
switch_new[10, :t_bus] = "10"
switch_new[10, :breaker] = true
switch_new[10, :closed] = false

# Make line 10
branch_new[10, :f_bus] = "8"
branch_new[10, :t_bus] = "11"
reldata_new[10, :f_bus] = "8"
reldata_new[10, :t_bus] = "11"
branch_new[10, π_line] = merge_branches(branch, 10:13)
reldata_new[10, rel_line] = merge_reldata(reldata, 10:13)
switch_new[11, :f_bus] = "8"
switch_new[11, :t_bus] = "11"

# Make line 11
branch_new[11, :f_bus] = "11"
branch_new[11, :t_bus] = "12"
reldata_new[11, :f_bus] = "11"
reldata_new[11, :t_bus] = "12"
branch_new[11, π_line] = merge_branches(branch, 70:72)
reldata_new[11, rel_line] = merge_reldata(reldata, 70:72)
switch_new[12, :f_bus] = "11"
switch_new[12, :t_bus] = "12"

# Make line 12
branch_new[12, :f_bus] = "11"
branch_new[12, :t_bus] = "13"
reldata_new[12, :f_bus] = "11"
reldata_new[12, :t_bus] = "13"
branch_new[12, π_line] = get_branch(case, "42", "44")[1, π_line]
reldata_new[12, rel_line] = get_branch_data(case, :reldata, "42", "44")[1, rel_line]
switch_new[13, :f_bus] = "11"
switch_new[13, :t_bus] = "13"

# Make line 13
branch_new[13, :f_bus] = "13"
branch_new[13, :t_bus] = "14"
reldata_new[13, :f_bus] = "13"
reldata_new[13, :t_bus] = "14"
branch_new[13, π_line] = merge_branches(branch, 14:15)
reldata_new[13, rel_line] = merge_reldata(reldata, 14:15)

# Make line 14
branch_new[14, :f_bus] = "14"
branch_new[14, :t_bus] = "15"
reldata_new[14, :f_bus] = "14"
reldata_new[14, :t_bus] = "15"
branch_new[14, π_line] = get_branch(case, "46", "47")[1, π_line]
reldata_new[14, rel_line] = get_branch_data(case, :reldata, "46", "47")[1, rel_line]

# Make line 15
branch_new[15, :f_bus] = "15"
branch_new[15, :t_bus] = "16"
reldata_new[15, :f_bus] = "15"
reldata_new[15, :t_bus] = "16"
branch_new[15, π_line] = merge_branches(branch, 14:15)
reldata_new[15, rel_line] = merge_reldata(reldata, 14:15)
switch_new[14, :f_bus] = "15"
switch_new[14, :t_bus] = "16"
switch_new[14, :closed] = false
switch_new[15, :f_bus] = "15"
switch_new[15, :t_bus] = "16"
switch_new[15, :breaker] = true
switch_new[15, :closed] = false

case_new = Case()
case_new.bus = bus_new
case_new.branch = branch_new
case_new.switch = switch_new
case_new.reldata = reldata_new
case_new.load = load_new
case_new.loaddata = loaddata_new
case_new.gen = gen_new

rename!(case_new.gen, :Pg => :P)

rename!(case_new.reldata, :r_perm => :repairTime)
rename!(case_new.reldata, :r_temp => :temporaryFaultTime)
rename!(case_new.reldata, :lambda_perm => :permanentFaultFrequency)
rename!(case_new.reldata, :lambda_temp => :temporaryFaultFrequency)

case_new.switch[!, :t_remote] .= 1/3600 # I set the remote switching time to 1 second
case_new.switch[!, :t_manual] .= 0.5 # I set the manual switching time to 30 minutes

rename!(case.reldata, :sectioning_time => :sectioningTime)

to_csv(case_new, "cineldi_simple")

