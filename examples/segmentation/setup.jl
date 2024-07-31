using RelDist: segment_network, segment_network_fast, segment_network_classic
using RelDist: t_load, t_nfc_load, t_supply, NewBranch, is_supply, is_nfc, is_switch
using RelDist: remove_switchless_branches!, labels
using RelDist: NetworkPart, empty_network, to_dot, dot_plot
using RelDist: kile_loss, energy_not_served, Bus, Network, KeyType
using RelDist: segment_network_ignore_overlap, get_start_guess_optimal
