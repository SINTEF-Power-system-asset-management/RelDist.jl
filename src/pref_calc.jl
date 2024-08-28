""" Calculate P_ref."""
function calculate_pref(
    fname_l::String,
    fname_reftime::String,
    fname_temp::String,
    interruption::Interruption,
    T_aver::Float64,
)::Interruption
    lp_type = interruption.customer.loadprofile_type
    c_type = interruption.customer.consumer_type
    annual_consumption = interruption.customer.annual_consumption
    start_time = interruption.start_time
    lp = read_loadprofile(fname_l, lp_type)
    T = parse_temperature(fname_temp)
    W_NRP = calculate_W_NRP(lp, start_time, T)
    W_RP = annual_consumption
    referencetime = get_referencetime(fname_reftime, c_type)
    pref = calculate_pref(lp, referencetime, W_RP, W_NRP, T_aver)
    interruption.customer.p_ref = pref
    return interruption
end

function calculate_pref(
    lp::DataFrame,
    referencetime::Dict,
    W_RP::Float64,
    W_NRP::Float64,
    T_aver::Float64,
)::Float64
    A, B = get_AB_ext(
        lp,
        get_season(referencetime["month"]),
        get_weekday(referencetime["day"]),
        Dates.DateTime(referencetime["hour"], "H:M"),
    )
    p_hprev = (A[1] * T_aver + B[1]) * W_RP / W_NRP
    p_h = (A[2] * T_aver + B[2]) * W_RP / W_NRP
    p_hsucc = (A[3] * T_aver + B[3]) * W_RP / W_NRP
    if (p_hprev <= p_h && p_h <= p_hsucc)
        return (p_hprev + p_h) / 2
    else
        return p_h
    end
end

function get_AB(
    lp::DataFrame,
    season::String,
    weekday::String,
    t::DateTime,
)::Tuple{Float64,Float64}
    h = Dates.hour(t) + 5  # the fifth column of the CSV correspond to time period 00:00 to 00:59
    A = lp[(lp.Month.==season).&(lp.Day.==weekday).&(lp.AB.=="A"), h]
    B = lp[(lp.Month.==season).&(lp.Day.==weekday).&(lp.AB.=="B"), h]
    return A[1], B[1]
end

function get_AB_ext(
    lp::DataFrame,
    season::String,
    weekday::String,
    t::DateTime,
)::Tuple{Array{Float64,2},Array{Float64,2}}
    h = Dates.hour(t) + 5  # the fifth column of the CSV correspond to time period 00:00 to 00:59
    A = Array(lp[(lp.Month.==season).&(lp.Day.==weekday).&(lp.AB.=="A"), [h - 1, h, h + 1]])
    B = Array(lp[(lp.Month.==season).&(lp.Day.==weekday).&(lp.AB.=="B"), [h - 1, h, h + 1]])
    return A, B
end

""" Calculate annual consumption related to load profile """
function calculate_W_NRP(lp::DataFrame, start_time::ZonedDateTime, T::DataFrame)::Float64
    year = Dates.year(start_time)  # I consider the measurement related to the previous year
    d = Dates.DateTime(year, 1, 1, 0):Dates.Hour(1):Dates.DateTime(year, 12, 31, 24)
    t = d.start
    temp = 1
    W_NRP = 0
    while t < d.stop
        temp = T[(T.referenceTime.==Dates.Date(t)), :][1, :value]
        season = get_season(t)
        weekday = get_weekday(t)
        A, B = get_AB(lp, season, weekday, t)
        W_NRP += max(0, (A * temp + B))  # If, due to T, this sum is negative, take 0
        t += d.step
    end
    return W_NRP
end


function get_season(t::DateTime)
    return (
        (
            Dates.monthname(t) != "January" &&
            Dates.monthname(t) != "February" &&
            Dates.monthname(t) != "December"
        ) ? "lowseason" : "highseason"
    )
end

function get_season(t::String)
    return (
        (t != "January" && t != "February" && t != "December") ? "lowseason" : "highseason"
    )
end

function get_weekday(t::DateTime)
    return (
        (Dates.dayname(t) != "Saturday" && Dates.dayname(t) != "Sunday") ? "hverdag" :
        "helg"
    )
end

function get_weekday(t::String)
    if t == "hverdag" || t == "helg"
        return t
    else
        return ((t != "Saturday" && t != "Sunday") ? "hverdag" : "helg")
    end
end
