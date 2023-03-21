
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
    U::Matrix{<:Real}
    ENS::Matrix{<:Real}
    CENS::Matrix{<:Real}
end

"""
    Constructor for RelStruct.

    Arguments:
        n_loads: Number of loads in the case.
        n_branch: Number of branches.
"""
function RelStruct(n_loads::Integer, n_branch::Integer)
    RelStruct(zeros(n_loads, n_branch),
              zeros(n_loads, n_branch),
              zeros(n_loads, n_branch),
              zeros(n_loads, n_branch))
end

"""
    Set entries in the result matrix.
"""
function set_res!(res::RelStruct, t::Real, U::Real, ENS::Real, CENS::Real,
        load_pos::Integer, edge_pos::Integer)
    res.t[load_pos, edge_pos] = t
    res.U[load_pos, edge_pos] = U
    res.ENS[load_pos, edge_pos] = ENS
    res.CENS[load_pos, edge_pos] = CENS
end

