package enums

// Osmium buys these — unlike Saw/Gun/Strike turret levels (which stack),
// each is a one-time, unique pickup (see models/shop.odin's
// shop_render_boosts, drawn 2-at-a-time like the turret gold cards). They're
// deliberately narrow and situational rather than flat stat bumps, so
// picking one over another is a real build choice, and some are designed to
// combo directly with each other (MomentumCells feeds StarvedEdge;
// ReinforcedHull enables ProspectorsMomentum as a real mining strategy
// instead of a liability).
BoostType :: enum {
    MomentumCells = 0,
    StarvedEdge,
    ReinforcedHull,
    ProspectorsMomentum,
    VampiricSaw,
    ChainReaction,
    AdrenalineRush,
}

boost_name :: proc(boost: BoostType) -> cstring {
    switch boost {
        case .MomentumCells:        return "Momentum Cells"
        case .StarvedEdge:          return "Starved Edge"
        case .ReinforcedHull:       return "Reinforced Hull"
        case .ProspectorsMomentum:  return "Prospector's Momentum"
        case .VampiricSaw:          return "Vampiric Saw"
        case .ChainReaction:        return "Chain Reaction"
        case .AdrenalineRush:       return "Adrenaline Rush"
    }
    return ""
}

boost_description :: proc(boost: BoostType) -> cstring {
    switch boost {
        case .MomentumCells:        return "Strike drone hits refuel the ship a little."
        case .StarvedEdge:          return "Laser damage scales with fuel level (50%-200%)."
        case .ReinforcedHull:       return "Ramming a meteor no longer damages the ship."
        case .ProspectorsMomentum:  return "Ramming a meteor mines it far more aggressively."
        case .VampiricSaw:          return "Saw kills heal a sliver of hull."
        case .ChainReaction:        return "Minigun kills burst, damaging nearby bots."
        case .AdrenalineRush:       return "Max speed rises the lower your hull gets."
    }
    return ""
}
