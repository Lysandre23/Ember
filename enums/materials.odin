package enums

import rl "vendor:raylib"

IRON_COLOR :: rl.Color { 99, 110, 114, 255 }
SILVER_COLOR :: rl.Color { 223, 230, 233, 255 }
GOLD_COLOR :: rl.Color { 255, 234, 167, 255 }
OSMIUM_COLOR :: rl.Color { 108, 92, 231, 255 }

Materials :: enum {
    Iron = 0,
    Silver,
    Gold,
    Osmium
}

material_color :: proc(material: Materials) -> rl.Color {
    switch material {
        case Materials.Iron: return IRON_COLOR
        case Materials.Silver: return SILVER_COLOR
        case Materials.Gold: return GOLD_COLOR
        case Materials.Osmium: return OSMIUM_COLOR
    }
    return rl.RAYWHITE
}

material_name :: proc(material: Materials) -> cstring {
    switch material {
        case Materials.Iron: return "Iron"
        case Materials.Silver: return "Silver"
        case Materials.Gold: return "Gold"
        case Materials.Osmium: return "Osmium"
    }
    return ""
}

material_presence :: proc(material: Materials) -> int {
    switch material {
        case Materials.Iron: return 50
        case Materials.Silver: return 30
        case Materials.Gold: return 15
        case Materials.Osmium: return 5
    }
    return 0
}

// 0 (as common as Iron) to 1 (as scarce as Osmium) — derived from
// material_presence rather than a second hand-tuned table, so rarity always
// tracks whatever spawn weights are actually in play.
material_rarity :: proc(material: Materials) -> f32 {
    most_common := f32(material_presence(Materials.Iron))
    rarest := f32(material_presence(Materials.Osmium))
    presence := f32(material_presence(material))
    return (most_common - presence) / (most_common - rarest)
}