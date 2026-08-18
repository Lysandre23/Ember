package models

import rl "vendor:raylib"
import "core:math"
import "../utils"

ACTIVE_COLOR :: rl.Color { 26, 188, 156, 255 }
POI_RADIUS :: 50
HEAL_SPEED :: 2

Poi :: struct {
    type: PoiType,
    active: bool,
    position: [2]f32
}

PoiType :: enum {
    Shop = 0,
    Heal,
    Extract
}

poi_update :: proc(poi: ^Poi, ship: ^Ship, dt: f32) {
    poi.active = utils.vec2_dist(poi.position, ship.position) < POI_RADIUS
    if poi.active {
        #partial switch poi.type {
            case PoiType.Heal:
                ship.integrity = clamp(ship.integrity + HEAL_SPEED * dt, 0, ship.max_integrity)
        }
    }
}

// Extract's own accent — Shop/Heal are plain white until the ship is in
// range, but an extraction gate is rare (EXTRACT_POI_NUMBER) and important
// enough that it should read as a landmark from a distance instead of
// blending into every other white polygon in the field.
EXTRACT_COLOR :: rl.Color { 255, 195, 60, 220 }

poi_render :: proc(poi: ^Poi) {
    color := poi.active ? ACTIVE_COLOR : rl.RAYWHITE
    if poi.type == PoiType.Extract && !poi.active {
        color = EXTRACT_COLOR
    }
    switch poi.type {
        case PoiType.Shop:
            rl.DrawPolyLinesEx(poi.position, 6, POI_RADIUS, 0, 3, color)
            rl.DrawPolyLinesEx(poi.position, 4, POI_RADIUS / 2, 45, 3, color)
        case PoiType.Heal:
            rl.DrawPolyLinesEx(poi.position, 6, POI_RADIUS, 0, 3, color)
            heal_thick: f32 = 8
            rl.DrawRectangleRounded(
                rl.Rectangle {
                    poi.position.x - heal_thick,
                    poi.position.y - POI_RADIUS / 2,
                    heal_thick * 2, POI_RADIUS
                },
                5, 5, color
            )
            rl.DrawRectangleRounded(
                rl.Rectangle {
                    poi.position.x - POI_RADIUS / 2,
                    poi.position.y - heal_thick,
                    POI_RADIUS, heal_thick * 2
                },
                5, 5, color
            )
        case PoiType.Extract:
            // A slowly spinning gate, distinct from Shop's static hexagon and
            // Heal's cross, to read as a portal rather than a building.
            spin := f32(rl.GetTime()) * 40
            rl.DrawPolyLinesEx(poi.position, 8, POI_RADIUS, spin, 3, color)
            rl.DrawPolyLinesEx(poi.position, 3, POI_RADIUS * 0.5, -spin * 1.5, 3, color)
    }
}