package models

import "core:fmt"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"
import "../utils"

// Exactly one per map — it's the single goal, not a resource like Heal/Shop,
// so more than one would just be noise.
EXTRACT_POI_NUMBER :: 1
// The extract point is placed within this radius of wherever the ship
// starts the map, instead of uniformly at random across the whole
// 10000x10000 level like Heal/Shop — a fully random placement could land it
// a full map away from a fresh spawn, making the goal effectively
// unreachable without blind exploration.
EXTRACT_MAX_SPAWN_DIST :: 4000
EXTRACT_PLACEMENT_TRIES :: 60

// Unlike level_spawn_poi's rejection sampling (which just skips a POI it
// couldn't place after a handful of tries), this is the one thing on the map
// that MUST exist — a map that silently ended up with zero extraction points
// is a dead end. Candidates are still preferred at least MIN_RANGE_BETWEEN_POI
// from every other POI, but if EXTRACT_PLACEMENT_TRIES worth of attempts (near
// spawn, so still reachable) never finds a fully clear spot — plausible if
// Heal/Shop happened to cluster near the ship's start — the least-crowded
// candidate seen is used instead of placing nothing.
level_spawn_extract_pois :: proc(level: ^Level) {
    best_position: [2]f32
    best_clearance := f32(-1)

    for _ in 0..<EXTRACT_PLACEMENT_TRIES {
        angle := rand.float32() * math.TAU
        radius := rand.float32() * EXTRACT_MAX_SPAWN_DIST
        position := level.ship.position + [2]f32 {math.cos(angle), math.sin(angle)} * radius
        position.x = clamp(position.x, 0, LEVEL_WIDTH)
        position.y = clamp(position.y, 0, LEVEL_HEIGHT)

        clearance := f32(1e9)
        for poi in level.pois {
            d := utils.vec2_dist(poi.position, position)
            if d < clearance {
                clearance = d
            }
        }

        if clearance >= MIN_RANGE_BETWEEN_POI {
            append(&level.pois, Poi { active = false, position = position, type = PoiType.Extract })
            return
        }
        if clearance > best_clearance {
            best_clearance = clearance
            best_position = position
        }
    }

    append(&level.pois, Poi { active = false, position = best_position, type = PoiType.Extract })
}

// Docking on an Extract poi (models/poi.odin) offers a choice rather than
// firing immediately — same open/dismissed pattern as the shop
// (models/shop.odin's level_update_shop_trigger) so the ship can sit on the
// beacon without instantly warping, and choosing "Stay" doesn't retrigger
// the prompt until the ship actually leaves the radius.
level_update_extract_trigger :: proc(level: ^Level) {
    near_extract := false
    for poi in level.pois {
        if poi.type != PoiType.Extract || !poi.active {
            continue
        }
        near_extract = true
        if !level.extract_dismissed {
            level.extract_open = true
        }
    }
    if !near_extract {
        level.extract_dismissed = false
    }
}

// Immediate-mode panel, same style/click handling as shop_render — only ever
// drawn while level.extract_open is true, which is itself only true while
// the game is paused (level_update's pause flag), so there's no risk of a
// click here also reaching the world underneath.
extract_render :: proc(hud: Hud, level: ^Level) {
    mouse := rl.GetMousePosition()
    clicked := rl.IsMouseButtonPressed(.LEFT)

    rl.DrawRectangleRec(rl.Rectangle {0, 0, hud.width, hud.height}, rl.Color {4, 4, 8, 235})

    panel_w := min(hud.width - 80, 560)
    panel_h : f32 = 220
    panel_x := (hud.width - panel_w) / 2
    panel_y := (hud.height - panel_h) / 2
    panel := rl.Rectangle {panel_x, panel_y, panel_w, panel_h}

    rl.DrawRectangleRounded(panel, 0.05, 8, rl.Color {14, 14, 20, 250})
    rl.DrawRectangleRoundedLinesEx(panel, 0.05, 8, 1.5, ACTIVE_COLOR)

    rl.DrawTextEx(hud.font, "EXTRACTION POINT", [2]f32 {panel_x + 24, panel_y + 20}, 22, 1, rl.RAYWHITE)

    sector_text := fmt.ctprintf("Map %d cleared. Jump to Map %d?", level.map_tier, level.map_tier + 1)
    rl.DrawTextEx(hud.font, sector_text, [2]f32 {panel_x + 24, panel_y + 60}, 15, 1, HUD_TEXT_COLOR)

    hint_text: cstring = "Bots grow stronger with every jump — your ship keeps every upgrade, drone and turret."
    rl.DrawTextEx(hud.font, hint_text, [2]f32 {panel_x + 24, panel_y + 84}, 12, 1, HUD_LABEL_COLOR)

    button_y := panel_y + panel_h - 60
    stay_bounds := rl.Rectangle {panel_x + 24, button_y, (panel_w - 48) * 0.35, 40}
    jump_bounds := rl.Rectangle {panel_x + 24 + (panel_w - 48) * 0.4, button_y, (panel_w - 48) * 0.6, 40}

    if shop_button(hud, stay_bounds, "Stay", true, mouse, clicked) || rl.IsKeyPressed(.ESCAPE) {
        level.extract_open = false
        level.extract_dismissed = true
    }
    if shop_button(hud, jump_bounds, "Jump to next map", true, mouse, clicked) {
        level.extract_open = false
        level_advance_map(level)
    }
}

// A small arrowhead ringing the minimap, pointing at the nearest Extract
// poi with its distance — so the goal stays trackable during normal flight
// instead of only being visible by repeatedly opening the full map (TAB).
extract_render_compass :: proc(hud: Hud, level: Level, minimap_origin: [2]f32, minimap_size: f32) {
    nearest_dist := f32(1e9)
    nearest_pos: [2]f32
    found := false
    for poi in level.pois {
        if poi.type != PoiType.Extract {
            continue
        }
        d := utils.vec2_dist(poi.position, level.ship.position)
        if d < nearest_dist {
            nearest_dist = d
            nearest_pos = poi.position
            found = true
        }
    }
    if !found {
        return
    }

    center := minimap_origin + minimap_size * 0.5
    angle := math.atan2(nearest_pos.y - level.ship.position.y, nearest_pos.x - level.ship.position.x)
    dir := [2]f32 {math.cos(angle), math.sin(angle)}
    tip := center + dir * (minimap_size * 0.5 + 12)
    left := tip + utils.rotate_vec2_around([2]f32 {-9, -4}, {0, 0}, angle)
    right := tip + utils.rotate_vec2_around([2]f32 {-9, 4}, {0, 0}, angle)
    rl.DrawTriangle(tip, right, left, EXTRACT_COLOR)

    dist_text := fmt.ctprintf("%.0f", nearest_dist)
    rl.DrawTextEx(hud.font, dist_text, tip + dir * 12 - [2]f32 {10, 5}, 10, 1, EXTRACT_COLOR)
}
