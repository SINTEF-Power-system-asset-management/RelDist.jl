
"""
    Struct for storing reliability indices

    The results are stored in a matrix where each row represents a load
    and each column a branch that is out and may result in an outage of a load.

    t: This is the time the interruption lasts for a load.
    U: This is the unavailability of a load.
    ENS: This is the energy not supplied for a load.
    CENS: This the cost of energy not supplied.
"""
mutable struct RelStruct
    t::Matrix{<:Real}
    λ::Matrix{<:Real}
    P::Matrix{<:Real}
    U::Matrix{<:Real}
    ENS::Matrix{<:Real}
    IC::Matrix{<:Real}
    CENS::Matrix{<:Real}
    prob::Real
end

"""
    Constructor for RelStruct.

    Arguments:
        n_loads: Number of loads in the case.
        n_branch: Number of branches.
"""
function RelStruct(n_loads::Integer, n_branch::Integer, prob::Real)
    RelStruct(zeros(n_loads, n_branch),
              zeros(n_loads, n_branch),
              zeros(n_loads, n_branch),
              zeros(n_loads, n_branch),
              zeros(n_loads, n_branch),
              zeros(n_loads, n_branch),
              zeros(n_loads, n_branch),
              prob)
end

function RelStruct(n_loads::Integer, n_branch::Integer)
    RelStruct(n_loads, n_branch, 1)
end

"""
    Set entries in the result matrix.
"""
function set_res!(res::RelStruct, λ::Real, t::Real, P::Real, U::Real,
        ENS::Real, IC::Real, CENS::Real,
        load_pos::Integer, edge_pos::Integer)
    res.t[load_pos, edge_pos] = t
    res.λ[load_pos, edge_pos] = λ
    res.P[load_pos, edge_pos] = P
    res.U[load_pos, edge_pos] = U
    res.ENS[load_pos, edge_pos] = ENS
    res.IC[load_pos, edge_pos] = IC
    res.CENS[load_pos, edge_pos] = CENS
end

"""
    Struct for storing reliability indices

    The results are stored in dataframes.

    U: This is the unavailability of a load.
    ENS: This is the energy not supplied for a load.
    CENS: This the cost of energy not supplied.
"""
mutable struct ResFrames
    U::DataFrame
    ENS::DataFrame
    IC::DataFrame
    CENS::DataFrame
    load_agg::DataFrame
    branch_agg::DataFrame
    sys_agg::DataFrame

end

function ResFrames()
	ResFrames(DataFrame(), DataFrame(), DataFrame(), DataFrame(), DataFrame(), DataFrame(),
              DataFrame())
end

function ResFrames(res::Dict{String, RelStruct}, edge_pos::DataFrame,
        L::Vector{RelDist.Load})
    # Put everything into nice dataframes
    res_new = ResFrames()

    load_labels = [load.ID for load in L]
    branch_agg = DataFrame(ID=edge_pos.name)
    load_agg = DataFrame(ID=load_labels)

    for field in [:U, :ENS, :CENS]
        frame = DataFrame(zeros(length(L), size(edge_pos, 1)),
                          edge_pos.name, makeunique=true)
        for key in keys(res)
            frame .+= getfield(res[key], field)*res[key].prob
        end
        insertcols!(frame, 1, :L=>load_labels);
        setfield!(res_new, field, frame)

        branch_agg[!, field] = sum.(eachcol(frame[:,2:end]))
        load_agg[!, field] = sum.(eachrow(frame[!,2:end]))
    end
    setfield!(res_new, :load_agg, load_agg)
    setfield!(res_new, :branch_agg, branch_agg)
    setfield!(res_new,
              :sys_agg,
              DataFrame(sum.(eachcol(load_agg[:, 2:end]))',
                        [:U, :ENS, :CENS]))
    return res_new
end

