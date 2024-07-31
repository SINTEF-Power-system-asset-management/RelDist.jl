using RelDist:
    segment_network_classic,
    empty_network,
    Bus,
    Network,
    KeyType
using RelDist: t_load, t_nfc_load, t_supply, NewBranch, is_supply, is_nfc, is_switch
using RelDist: remove_switchless_branches!, labels
using RelDist: NetworkPart, segment_network, to_dot, dot_plot
using RelDist: kile_loss, energy_not_served

