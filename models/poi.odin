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

poi_render :: proc(poi: ^Poi) {
    color := poi.active ? ACTIVE_COLOR : rl.RAYWHITE
    switch poi.type {
        case PoiType.Shop:
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
    }
}