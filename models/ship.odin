package models

import "core:math/rand"
import rl "vendor:raylib"
import "core:math"
import "../utils"
import "../enums"

SHIP_MAX_SPEED :: 250
SHIP_COLOR :: rl.Color { 255, 255, 255, 255 }
MAX_RANGE :: 100
LASER_IMPACT_PARTICLE_COUNT :: 3
LASER_IMPACT_PARTICLE_RELOAD :: 3

TRAIL_PARTICLE_COLOR :: rl.Color { 140, 200, 255, 220 }
TRAIL_BURST_COUNT :: 5
TRAIL_RELOAD :: 6
TRAIL_BASE_SPEED :: 40.0
TRAIL_SHIP_SPEED_INFLUENCE :: 1.2
TRAIL_SPREAD :: 0.4
TRAIL_LIFETIME_MIN :: 10
TRAIL_LIFETIME_MAX :: 26
TRAIL_START_RADIUS :: 3.5
TRAIL_END_RADIUS :: 0.5

Ship :: struct {
    position, speed, laser_target: [2]f32,
    vertices: [3][2]f32,
    trail_particles: [dynamic]Particle,
    trail_reload: u8,
    laser_on: bool,
    laser_color_variation: u8,
    laser_impact_reload: u8,
    laser_power, max_capacity, direction, integrity, max_integrity: f32,
    stocks: map[enums.Materials]f32,
}

ship_update :: proc(ship: ^Ship, meteors: []Meteor, active_meteor_ids: []int, new_meteors: ^[dynamic]Meteor, destroyed_meteor_ids: ^[dynamic]int, impact_particles: ^[dynamic]Particle, camera: rl.Camera2D, dt: f32) {
    acc: f32 = 200

    if rl.IsKeyDown(.W) {
        ship.speed.x += math.cos(ship.direction) * acc * dt
        ship.speed.y += math.sin(ship.direction) * acc * dt
        trail_particle_spawn(ship)
    }
    if rl.IsKeyDown(.S) {
        ship.speed *= math.pow(f32(0.1), dt)
    }
    mouse := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
    mouse_vector := [2]f32 {mouse.x - ship.position.x, mouse.y - ship.position.y}
    ship.direction = math.atan2_f32(mouse_vector.y, mouse_vector.x)
    ship.speed = utils.vec2_clamp_length(ship.speed, SHIP_MAX_SPEED)
    ship.position += ship.speed * dt
    if ship.position.x < 0 || ship.position.x > LEVEL_WIDTH {
        ship.position.x = clamp(ship.position.x, 0, LEVEL_WIDTH)
        ship.speed.x = 0
    }
    if ship.position.y < 0 || ship.position.y > LEVEL_HEIGHT {
        ship.position.y = clamp(ship.position.y, 0, LEVEL_HEIGHT)
        ship.speed.y = 0
    }
    ship.vertices = ship_get_vertices(ship^)
    particle_update(&ship.trail_particles, dt)

    if rl.IsMouseButtonDown(.LEFT) {
        ship.laser_on = true
        if ship.laser_power < MAX_RANGE {
            ship.laser_power += 2
        }
        ship.laser_target = ship.vertices[2] + [2]f32 { 
            math.cos(ship.direction) * ship.laser_power,
            math.sin(ship.direction) * ship.laser_power
        }
        laser_hit_meteor(ship, meteors, active_meteor_ids, new_meteors, destroyed_meteor_ids, impact_particles, dt)
    } else {
        ship.laser_on = false
        ship.laser_power = 0
    }
}

ship_render :: proc(ship: Ship) {
    thickness: f32 = 2
    rl.DrawLineEx(ship.vertices[0], ship.vertices[1], thickness, SHIP_COLOR)
    rl.DrawLineEx(ship.vertices[1], ship.vertices[2], thickness, SHIP_COLOR)
    rl.DrawLineEx(ship.vertices[2], ship.vertices[0], thickness, SHIP_COLOR)
    particle_render(ship.trail_particles)
    if (ship.laser_on) {
        rl.DrawLineEx(
            ship.vertices[2],
            ship.laser_target,
            1,
            SHIP_COLOR
        )
    }
}

ship_handle_hit :: proc(ship: ^Ship, position: [2]f32, damage: f32) {
    ship_take_damage(ship, 5)
}

ship_take_damage :: proc(ship: ^Ship, damage: f32) {
    ship.integrity -= damage
    if ship.integrity < 0 {
        ship.integrity = 0
    }
}

ship_get_vertices :: proc(ship: Ship) -> [3][2]f32 {
    size: f32 = 30
    origin := ship.position
    p1 := [2]f32 { ship.position.x - size / 2, ship.position.y - size / 3 }
    p2 := [2]f32 { ship.position.x - size / 2, ship.position.y + size / 3 }
    p3 := [2]f32 { ship.position.x + size / 2, ship.position.y }
    p1 = utils.rotate_vec2_around(p1, origin, ship.direction)
    p2 = utils.rotate_vec2_around(p2, origin, ship.direction)
    p3 = utils.rotate_vec2_around(p3, origin, ship.direction)
    return [3][2]f32 {p1, p2, p3}
}

// Emits a little pulse of engine bubbles every TRAIL_RELOAD frames while
// thrusting, instead of a smooth continuous drip — that's what reads as a
// pulse rather than a static streak. Each pulse's ejection speed scales with
// the ship's actual current speed (utils.norm_vec2(ship.speed)): the old
// version derived speed purely from ship.direction (a unit vector) times a
// fixed constant, so the bubbles always flew backward at the same rate no
// matter how fast — or whether — the ship was actually moving. Direction is
// still "backward from where the ship is facing" (that's the visually
// correct exhaust-nozzle direction) with a little random spread per bubble
// so a pulse reads as a small cone/poof, not a single thin line.
trail_particle_spawn :: proc(ship: ^Ship) {
    if ship.trail_reload > 0 {
        ship.trail_reload -= 1
        return
    }
    ship.trail_reload = TRAIL_RELOAD

    v1 := ship.vertices[0]
    v2 := ship.vertices[1]
    base := [2]f32 {
        (v1.x + v2.x) / 2,
        (v1.y + v2.y) / 2
    }

    ship_speed := utils.norm_vec2(ship.speed)
    eject_speed := TRAIL_BASE_SPEED + ship_speed * TRAIL_SHIP_SPEED_INFLUENCE

    for _ in 0..<TRAIL_BURST_COUNT {
        jitter := (rand.float32() * 2 - 1) * TRAIL_SPREAD
        angle := ship.direction + math.PI + jitter
        lifetime := TRAIL_LIFETIME_MIN + rand.int_max(TRAIL_LIFETIME_MAX - TRAIL_LIFETIME_MIN)
        append(&ship.trail_particles, Particle {
            position = base,
            speed = [2]f32 { math.cos(angle), math.sin(angle) } * eject_speed * (rand.float32() * 0.4 + 0.8),
            lifetime = lifetime,
            max_lifetime = lifetime,
            color = TRAIL_PARTICLE_COLOR,
            start_radius = TRAIL_START_RADIUS,
            end_radius = TRAIL_END_RADIUS,
        })
    }
}

laser_hit_meteor :: proc(ship: ^Ship, meteors: []Meteor, active_meteor_ids: []int, new_meteors: ^[dynamic]Meteor, destroyed_meteor_ids: ^[dynamic]int, impact_particles: ^[dynamic]Particle, dt: f32) {
    if ship.laser_impact_reload > 0 {
        ship.laser_impact_reload -= 1
    }

    // Only active meteors are visited — never the raw pool array. A meteor
    // destroyed by a split (models/level.odin's destroyed_meteor_ids cleanup)
    // gets pool_remove'd, which frees its vertices but leaves the freed slot
    // sitting in the pool until reused; walking the full array would sooner
    // or later touch that dangling slot and crash the way we just saw
    // ("pointer being freed was not allocated") once enough splitting had
    // built up dead slots. active_meteors always drops an id the same frame
    // it's destroyed, so a freed slot is never visited again.
    for id in active_meteor_ids {
        meteor := &meteors[id]
        if utils.vec2_dist(ship.laser_target, meteor.position) >= METEOR_MINIMUM_SIZE * 4 {
            continue
        }

        // The actual mining/deformation/splitting rules live on Meteor
        // (models/meteor.odin:meteor_hit) so any other component — a bot
        // colliding with a meteor, say — can damage one the same way without
        // duplicating this logic. Everything below is ship-specific: where
        // the beam visually stops, whose stockpile grows, and handing the
        // split/destroy result off to level_update for pool bookkeeping.
        impact, yield, fragments, destroyed, hit := meteor_hit(meteor, ship.position, ship.laser_target, dt)
        if !hit {
            continue
        }

        ship.laser_target = impact
        ship.stocks[meteor.material] += yield

        if ship.laser_impact_reload == 0 {
            particle_spawn_burst(impact_particles, impact, enums.material_color(meteor.material), LASER_IMPACT_PARTICLE_COUNT)
            ship.laser_impact_reload = LASER_IMPACT_PARTICLE_RELOAD
        }

        if destroyed {
            append(destroyed_meteor_ids, id)
        }
        for fragment in fragments {
            append(new_meteors, fragment)
        }
        delete(fragments)
    }
}