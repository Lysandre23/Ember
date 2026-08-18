package models

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"
import "../enums"

SHOP_POI_NUMBER :: 6

FUEL_COST_PER_UNIT   :: 0.15
ENERGY_COST_PER_UNIT :: 0.15

UPGRADE_MAX_LEVEL        :: 5
SPEED_UPGRADE_STEP       :: 25
DAMAGE_UPGRADE_STEP      :: 0.15
CAPACITY_UPGRADE_STEP    :: 40
SILVER_UPGRADE_BASE_COST :: 8
SILVER_UPGRADE_COST_STEP :: 8

TURRET_MAX_LEVEL    :: 5
GOLD_CARD_BASE_COST :: 10
GOLD_CARD_COST_STEP :: 6

PURCHASABLE_TURRETS := [3]enums.TurretType { enums.TurretType.Saw, enums.TurretType.Gun, enums.TurretType.Strike }

// Osmium boosts (enums/boost.odin) are one-time picks, not levels, so the
// cost curve is keyed on how many the ship already holds rather than a
// per-item level.
OSMIUM_BOOST_BASE_COST :: 15
OSMIUM_BOOST_COST_STEP :: 22

osmium_boost_cost :: proc(owned_count: int) -> f32 {
    return OSMIUM_BOOST_BASE_COST + f32(owned_count) * OSMIUM_BOOST_COST_STEP
}

// A full Fuel/Laser Energy gauge can't be raised any further with Iron —
// past that ceiling, Osmium buys real headroom instead (models/shop.odin's
// shop_consumable_row). Same capped, scaling-cost shape as the other Osmium/
// Silver/Gold purchases.
OSMIUM_EXPAND_MAX_LEVEL :: 5
OSMIUM_EXPAND_STEP      :: 30 // added to max_fuel/max_laser_energy per purchase
OSMIUM_EXPAND_BASE_COST :: 12
OSMIUM_EXPAND_COST_STEP :: 10

osmium_expand_cost :: proc(current_level: int) -> f32 {
    return OSMIUM_EXPAND_BASE_COST + f32(current_level) * OSMIUM_EXPAND_COST_STEP
}

// Docking on a Shop poi (models/poi.odin) freezes the sim exactly like the
// TAB map does (see level_update's pause flag) so the player can browse
// without pressure. level.shop_dismissed keeps a Leave'd shop from
// re-opening on the very next frame while the ship is still sitting in the
// same POI_RADIUS — it only clears once the ship actually leaves the radius,
// which in practice means flying away after resuming.
level_update_shop_trigger :: proc(level: ^Level) {
    near_shop := false
    for poi in level.pois {
        if poi.type != PoiType.Shop || !poi.active {
            continue
        }
        near_shop = true
        if !level.shop_dismissed {
            level.shop_open = true
        }
    }
    if !near_shop {
        level.shop_dismissed = false
    }
}

silver_upgrade_cost :: proc(current_level: int) -> f32 {
    return SILVER_UPGRADE_BASE_COST + f32(current_level) * SILVER_UPGRADE_COST_STEP
}

gold_card_cost :: proc(total_turret_levels: int) -> f32 {
    return GOLD_CARD_BASE_COST + f32(total_turret_levels) * GOLD_CARD_COST_STEP
}

apply_speed_upgrade :: proc(ship: ^Ship) {
    ship.max_speed += SPEED_UPGRADE_STEP
}

apply_damage_upgrade :: proc(ship: ^Ship) {
    ship.laser_damage_mult += DAMAGE_UPGRADE_STEP
}

apply_capacity_upgrade :: proc(ship: ^Ship) {
    ship.max_capacity += CAPACITY_UPGRADE_STEP
}

// Everything below draws AND handles clicks in the same pass (immediate-mode
// style, same idea as raygui) — it only ever runs from hud_render while
// level.shop_open is true, which is itself only true while the game is
// paused, so there's no risk of a click here also being consumed by the
// world underneath.
shop_render :: proc(hud: Hud, level: ^Level) {
    ship := &level.ship
    mouse := rl.GetMousePosition()
    clicked := rl.IsMouseButtonPressed(.LEFT)

    rl.DrawRectangleRec(rl.Rectangle {0, 0, hud.width, hud.height}, rl.Color {4, 4, 8, 235})

    panel_w := min(hud.width - 80, 1280)
    panel_h := min(hud.height - 80, 600)
    panel_x := (hud.width - panel_w) / 2
    panel_y := (hud.height - panel_h) / 2
    panel := rl.Rectangle {panel_x, panel_y, panel_w, panel_h}

    rl.DrawRectangleRounded(panel, 0.03, 8, rl.Color {14, 14, 20, 250})
    rl.DrawRectangleRoundedLinesEx(panel, 0.03, 8, 1.5, HUD_BORDER_COLOR)

    rl.DrawTextEx(hud.font, "SHOP", [2]f32 {panel_x + 24, panel_y + 20}, 26, 1, rl.RAYWHITE)
    shop_render_currencies(hud, ship^, panel_x + panel_w - 380, panel_y + 26)

    leave_bounds := rl.Rectangle {panel_x + panel_w - 100, panel_y + 20, 76, 30}
    if shop_button(hud, leave_bounds, "Leave", true, mouse, clicked) || rl.IsKeyPressed(.ESCAPE) {
        level.shop_open = false
        level.shop_dismissed = true
    }

    col_gap : f32 = 20
    col_w := (panel_w - col_gap * 5) / 4
    col_y := panel_y + 90
    col_h := panel_h - 110
    col1_x := panel_x + col_gap
    col2_x := col1_x + col_w + col_gap
    col3_x := col2_x + col_w + col_gap
    col4_x := col3_x + col_w + col_gap

    shop_render_consumables(hud, ship, rl.Rectangle {col1_x, col_y, col_w, col_h}, mouse, clicked)
    shop_render_upgrades(hud, ship, rl.Rectangle {col2_x, col_y, col_w, col_h}, mouse, clicked)
    shop_render_turrets(hud, level, rl.Rectangle {col3_x, col_y, col_w, col_h}, mouse, clicked)
    shop_render_boosts(hud, level, rl.Rectangle {col4_x, col_y, col_w, col_h}, mouse, clicked)
}

shop_render_currencies :: proc(hud: Hud, ship: Ship, x, y: f32) {
    materials := [4]enums.Materials {
        enums.Materials.Iron, enums.Materials.Silver,
        enums.Materials.Gold, enums.Materials.Osmium,
    }
    cursor_x := x
    for material in materials {
        rl.DrawPoly([2]f32 {cursor_x + 7, y + 8}, 6, 7, 0, enums.material_color(material))
        text := fmt.ctprintf("%.0f", ship.stocks[material])
        rl.DrawTextEx(hud.font, text, [2]f32 {cursor_x + 20, y}, 16, 1, HUD_TEXT_COLOR)
        cursor_x += 20 + rl.MeasureTextEx(hud.font, text, 16, 1).x + 20
    }
}

shop_button :: proc(hud: Hud, bounds: rl.Rectangle, label: cstring, enabled: bool, mouse: [2]f32, clicked: bool) -> bool {
    hovered := enabled && rl.CheckCollisionPointRec(mouse, bounds)
    bg := enabled ? (hovered ? rl.Color {64, 64, 78, 255} : rl.Color {34, 34, 44, 255}) : rl.Color {20, 20, 26, 255}
    border := enabled ? rl.Color {255, 255, 255, 70} : rl.Color {255, 255, 255, 20}
    text_color := enabled ? rl.RAYWHITE : rl.Color {120, 120, 130, 255}

    rl.DrawRectangleRounded(bounds, 0.25, 4, bg)
    rl.DrawRectangleRoundedLinesEx(bounds, 0.25, 4, 1, border)

    label_size : f32 = 14
    label_w := rl.MeasureTextEx(hud.font, label, label_size, 1).x
    label_h := rl.MeasureTextEx(hud.font, label, label_size, 1).y
    rl.DrawTextEx(
        hud.font, label,
        [2]f32 {bounds.x + (bounds.width - label_w) / 2, bounds.y + (bounds.height - label_h) / 2},
        label_size, 1, text_color
    )

    return hovered && clicked
}

shop_render_consumables :: proc(hud: Hud, ship: ^Ship, bounds: rl.Rectangle, mouse: [2]f32, clicked: bool) {
    rl.DrawTextEx(hud.font, "IRON - CONSUMABLES", [2]f32 {bounds.x, bounds.y}, 14, 1, HUD_LABEL_COLOR)

    y := bounds.y + 28
    y = shop_consumable_row(hud, ship, &ship.fuel, &ship.max_fuel, &ship.fuel_expand_level, "Fuel", bounds.x, y, bounds.width, mouse, clicked)
    y += 14
    y = shop_consumable_row(hud, ship, &ship.laser_energy, &ship.max_laser_energy, &ship.energy_expand_level, "Laser energy", bounds.x, y, bounds.width, mouse, clicked)
}

// Little blue blocks instead of one continuous fill — a segmented gauge
// reads more like an instrument readout, fitting the CRT/neon dashboard
// look, than a smooth progress bar does.
GAUGE_SEGMENT_COUNT :: 12
GAUGE_SEGMENT_GAP   :: 3

shop_consumable_row :: proc(hud: Hud, ship: ^Ship, current, max_val: ^f32, expand_level: ^int, label: cstring, x, y, width: f32, mouse: [2]f32, clicked: bool) -> f32 {
    rl.DrawTextEx(hud.font, label, [2]f32 {x, y}, 13, 1, HUD_TEXT_COLOR)
    if expand_level^ > 0 {
        level_text := fmt.ctprintf("+%d", expand_level^)
        level_w := rl.MeasureTextEx(hud.font, level_text, 12, 1).x
        rl.DrawTextEx(hud.font, level_text, [2]f32 {x + width - level_w, y + 1}, 12, 1, EXTRACT_COLOR)
    }

    bar_y := y + 18
    bar_h : f32 = 10
    ratio := current^ / max_val^
    filled_segments := int(ratio * GAUGE_SEGMENT_COUNT)
    seg_w := (width - GAUGE_SEGMENT_GAP * f32(GAUGE_SEGMENT_COUNT - 1)) / f32(GAUGE_SEGMENT_COUNT)

    for i in 0..<GAUGE_SEGMENT_COUNT {
        seg_x := x + f32(i) * (seg_w + GAUGE_SEGMENT_GAP)
        color := i < filled_segments ? rl.Color {100, 200, 255, 255} : rl.Color {255, 255, 255, 25}
        rl.DrawRectangleRounded(rl.Rectangle {seg_x, bar_y, seg_w, bar_h}, 0.4, 3, color)
    }

    missing := max_val^ - current^
    button_bounds := rl.Rectangle {x, bar_y + 18, width, 34}

    if missing > 0.5 {
        cost := missing * FUEL_COST_PER_UNIT
        label_text := fmt.ctprintf("Refill (%.0f Iron)", cost)
        have := ship.stocks[enums.Materials.Iron]
        if shop_button(hud, button_bounds, label_text, have > 0, mouse, clicked) {
            fraction := min(f32(1), have / cost)
            amount := missing * fraction
            current^ += amount
            ship.stocks[enums.Materials.Iron] -= amount * FUEL_COST_PER_UNIT
        }
    } else if expand_level^ >= OSMIUM_EXPAND_MAX_LEVEL {
        shop_button(hud, button_bounds, "Maxed", false, mouse, clicked)
    } else {
        // Full, and Iron can't raise the ceiling any further — Osmium buys
        // real headroom instead (models/shop.odin's OSMIUM_EXPAND_* consts),
        // topping the gauge off to the new max so expanding always feels
        // like a gain, never a step backward in fill ratio.
        cost := osmium_expand_cost(expand_level^)
        label_text := fmt.ctprintf("Expand (%.0f Osmium)", cost)
        if shop_button(hud, button_bounds, label_text, ship.stocks[enums.Materials.Osmium] >= cost, mouse, clicked) {
            ship.stocks[enums.Materials.Osmium] -= cost
            expand_level^ += 1
            max_val^ += OSMIUM_EXPAND_STEP
            current^ = max_val^
        }
    }

    return button_bounds.y + button_bounds.height
}

shop_render_upgrades :: proc(hud: Hud, ship: ^Ship, bounds: rl.Rectangle, mouse: [2]f32, clicked: bool) {
    rl.DrawTextEx(hud.font, "SILVER - SHIP UPGRADES", [2]f32 {bounds.x, bounds.y}, 14, 1, HUD_LABEL_COLOR)

    y := bounds.y + 28
    y = shop_upgrade_row(hud, ship, &ship.speed_level, "Speed", bounds.x, y, bounds.width, mouse, clicked, apply_speed_upgrade)
    y += 14
    y = shop_upgrade_row(hud, ship, &ship.damage_level, "Laser damage", bounds.x, y, bounds.width, mouse, clicked, apply_damage_upgrade)
    y += 14
    y = shop_upgrade_row(hud, ship, &ship.capacity_level, "Cargo capacity", bounds.x, y, bounds.width, mouse, clicked, apply_capacity_upgrade)
}

shop_upgrade_row :: proc(hud: Hud, ship: ^Ship, level_ptr: ^int, label: cstring, x, y, width: f32, mouse: [2]f32, clicked: bool, apply: proc(^Ship)) -> f32 {
    rl.DrawTextEx(hud.font, label, [2]f32 {x, y}, 13, 1, HUD_TEXT_COLOR)
    level_text := fmt.ctprintf("Lv %d/%d", level_ptr^, UPGRADE_MAX_LEVEL)
    level_w := rl.MeasureTextEx(hud.font, level_text, 13, 1).x
    rl.DrawTextEx(hud.font, level_text, [2]f32 {x + width - level_w, y}, 13, 1, HUD_LABEL_COLOR)

    button_bounds := rl.Rectangle {x, y + 20, width, 34}

    if level_ptr^ >= UPGRADE_MAX_LEVEL {
        shop_button(hud, button_bounds, "Maxed", false, mouse, clicked)
    } else {
        cost := silver_upgrade_cost(level_ptr^)
        label_text := fmt.ctprintf("Upgrade (%.0f Silver)", cost)
        if shop_button(hud, button_bounds, label_text, ship.stocks[enums.Materials.Silver] >= cost, mouse, clicked) {
            ship.stocks[enums.Materials.Silver] -= cost
            level_ptr^ += 1
            apply(ship)
        }
    }

    return button_bounds.y + button_bounds.height
}

shop_render_turrets :: proc(hud: Hud, level: ^Level, bounds: rl.Rectangle, mouse: [2]f32, clicked: bool) {
    ship := &level.ship
    rl.DrawTextEx(hud.font, "GOLD - TURRETS", [2]f32 {bounds.x, bounds.y}, 14, 1, HUD_LABEL_COLOR)

    y := bounds.y + 28
    total_levels := 0
    for i in 0..<len(enums.TurretType) {
        t := enums.TurretType(i)
        lvl := ship.turret_levels[t]
        total_levels += lvl
        status := lvl == 0 ? fmt.ctprintf("%s: not owned", enums.turret_name(t)) : fmt.ctprintf("%s: Lv %d", enums.turret_name(t), lvl)
        rl.DrawTextEx(hud.font, status, [2]f32 {bounds.x, y}, 13, 1, HUD_TEXT_COLOR)
        y += 20
    }
    y += 16

    if level.cards_pending {
        rl.DrawTextEx(hud.font, "Pick one:", [2]f32 {bounds.x, y}, 13, 1, HUD_LABEL_COLOR)
        y += 22
        for i in 0..<2 {
            card_type := level.card_offers[i]
            owned_level := ship.turret_levels[card_type]
            title: cstring
            if owned_level > 0 {
                title = fmt.ctprintf("Upgrade: %s (Lv %d)", enums.turret_name(card_type), owned_level + 1)
            } else {
                title = fmt.ctprintf("New: %s", enums.turret_name(card_type))
            }
            card_bounds := rl.Rectangle {bounds.x, y, bounds.width, 46}
            if shop_button(hud, card_bounds, title, owned_level < TURRET_MAX_LEVEL, mouse, clicked) {
                ship.turret_levels[card_type] += 1
                level.cards_pending = false
            }
            y += 46 + 10
        }
    } else {
        cost := gold_card_cost(total_levels)
        label_text := fmt.ctprintf("Draw 2 cards (%.0f Gold)", cost)
        button_bounds := rl.Rectangle {bounds.x, y, bounds.width, 38}
        if shop_button(hud, button_bounds, label_text, ship.stocks[enums.Materials.Gold] >= cost, mouse, clicked) {
            ship.stocks[enums.Materials.Gold] -= cost
            level.card_offers[0] = PURCHASABLE_TURRETS[rand.int_max(len(PURCHASABLE_TURRETS))]
            level.card_offers[1] = PURCHASABLE_TURRETS[rand.int_max(len(PURCHASABLE_TURRETS))]
            level.cards_pending = true
        }
    }
}

// Picks 2 boosts the ship doesn't already own, without duplicates unless
// only one remains unowned (in which case both slots show it — the render
// side disables whichever slot's already been bought before the other is
// clicked, see shop_render_boosts). ok is false once every boost is owned.
shop_draw_boost_offers :: proc(ship: Ship) -> (offers: [2]enums.BoostType, ok: bool) {
    available := make([dynamic]enums.BoostType, 0, len(enums.BoostType), context.temp_allocator)
    for i in 0..<len(enums.BoostType) {
        b := enums.BoostType(i)
        if b not_in ship.boosts {
            append(&available, b)
        }
    }
    if len(available) == 0 {
        return {}, false
    }

    offers[0] = available[rand.int_max(len(available))]
    offers[1] = available[rand.int_max(len(available))]
    tries := 0
    for offers[1] == offers[0] && len(available) > 1 && tries < 10 {
        offers[1] = available[rand.int_max(len(available))]
        tries += 1
    }
    ok = true
    return
}

shop_render_boosts :: proc(hud: Hud, level: ^Level, bounds: rl.Rectangle, mouse: [2]f32, clicked: bool) {
    ship := &level.ship
    rl.DrawTextEx(hud.font, "OSMIUM - RARE BOOSTS", [2]f32 {bounds.x, bounds.y}, 14, 1, HUD_LABEL_COLOR)

    y := bounds.y + 26
    owned_count := 0
    for i in 0..<len(enums.BoostType) {
        b := enums.BoostType(i)
        if b not_in ship.boosts {
            continue
        }
        owned_count += 1
        rl.DrawTextEx(hud.font, enums.boost_name(b), [2]f32 {bounds.x, y}, 12, 1, HUD_TEXT_COLOR)
        y += 16
    }
    if owned_count == 0 {
        rl.DrawTextEx(hud.font, "None yet", [2]f32 {bounds.x, y}, 12, 1, HUD_LABEL_COLOR)
        y += 16
    }
    y += 14

    if level.boost_cards_pending {
        rl.DrawTextEx(hud.font, "Pick one:", [2]f32 {bounds.x, y}, 13, 1, HUD_LABEL_COLOR)
        y += 20
        for i in 0..<2 {
            boost := level.boost_card_offers[i]
            already_owned := boost in ship.boosts
            card_bounds := rl.Rectangle {bounds.x, y, bounds.width, 34}
            label := already_owned ? fmt.ctprintf("%s (owned)", enums.boost_name(boost)) : enums.boost_name(boost)
            if shop_button(hud, card_bounds, label, !already_owned, mouse, clicked) {
                ship.boosts += {boost}
                level.boost_cards_pending = false
            }
            y += 34 + 2
            rl.DrawTextEx(hud.font, enums.boost_description(boost), [2]f32 {bounds.x, y}, 10, 1, HUD_LABEL_COLOR)
            y += 24
        }
    } else {
        _, any_left := shop_draw_boost_offers(ship^)
        if !any_left {
            rl.DrawTextEx(hud.font, "All boosts acquired", [2]f32 {bounds.x, y}, 13, 1, HUD_LABEL_COLOR)
        } else {
            cost := osmium_boost_cost(owned_count)
            label_text := fmt.ctprintf("Draw 2 boosts (%.0f Osmium)", cost)
            button_bounds := rl.Rectangle {bounds.x, y, bounds.width, 38}
            if shop_button(hud, button_bounds, label_text, ship.stocks[enums.Materials.Osmium] >= cost, mouse, clicked) {
                offers, ok := shop_draw_boost_offers(ship^)
                if ok {
                    ship.stocks[enums.Materials.Osmium] -= cost
                    level.boost_card_offers = offers
                    level.boost_cards_pending = true
                }
            }
        }
    }
}
