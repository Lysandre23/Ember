package models

import "core:math/rand"
import rl "vendor:raylib"
import "core:math"
import "../utils"
import "../enums"

SHIP_MAX_SPEED :: 250
SHIP_COLOR :: rl.Color { 255, 255, 255, 255 }
TRAIL_PARTICLE_COLOR :: rl.Color { 255, 255, 255, 100 }
MAX_RANGE :: 100

Ship :: struct {
    position, speed, laser_target: [2]f32,
    vertices: [3][2]f32,
    trail: Trail,
    laser_on: bool,
    laser_color_variation: u8,
    laser_power, max_capacity, direction, integrity, max_integrity: f32,
    stocks: map[enums.Materials]f32,
}

Trail :: struct {
    particles: [dynamic]TrailParticle,
    reload: u8
}

TrailParticle :: struct {
    position: [2]f32,
    speed: [2]f32,
    lifetime: int
}

ship_update :: proc(ship: ^Ship, meteors: []Meteor, camera: rl.Camera2D, dt: f32) {
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
    ship.vertices = ship_get_vertices(ship^)
    trail_update(&ship.trail, dt)

    if rl.IsMouseButtonDown(.LEFT) {
        ship.laser_on = true
        if ship.laser_power < MAX_RANGE {
            ship.laser_power += 2
        }
        ship.laser_target = ship.vertices[2] + [2]f32 { 
            math.cos(ship.direction) * ship.laser_power,
            math.sin(ship.direction) * ship.laser_power
        }
        laser_hit_meteor(ship, meteors, dt)
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
    trail_render(ship.trail)
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

trail_update :: proc(trail: ^Trail, dt: f32) {
    #reverse for &particle, i in trail.particles {
        particle.lifetime -= 1
        if particle.lifetime == 0 {
            unordered_remove(&trail.particles, i)
        }
        particle.position += particle.speed * dt
    }
    if trail.reload > 0 {
        trail.reload -= 1
    }
}

trail_render :: proc(trail: Trail) {
    for p in trail.particles {
        rl.DrawPixelV(p.position, TRAIL_PARTICLE_COLOR)
        rl.DrawPixelV(p.position + [2]f32 {0, 1}, TRAIL_PARTICLE_COLOR)
        rl.DrawPixelV(p.position + [2]f32 {0, -1}, TRAIL_PARTICLE_COLOR)
        rl.DrawPixelV(p.position + [2]f32 {1, 0}, TRAIL_PARTICLE_COLOR)
        rl.DrawPixelV(p.position + [2]f32 {-1, 0}, TRAIL_PARTICLE_COLOR)
    }
}

trail_particle_spawn :: proc(ship: ^Ship) {
    v1 := ship.vertices[0]
    v2 := ship.vertices[1]
    base := [2]f32 {
        (v1.x + v2.x) / 2,
        (v1.y + v2.y) / 2
    }

    base_direction := [2]f32 {
        math.cos(ship.direction),
        math.sin(ship.direction)
    }
    if ship.trail.reload <= 0 {
        append(
            &ship.trail.particles, 
            TrailParticle {
                position = base,
                speed = [2]f32 {
                    -base_direction.x * (f32(rand.int31_max(40)) / 100 + 0.8),
                    -base_direction.y * (f32(rand.int31_max(40)) / 100 + 0.8)
                } * 300,
                lifetime = rand.int_max(200)
            }
        )
        ship.trail.reload = 3
    }
}

laser_hit_meteor :: proc(ship: ^Ship, meteors: []Meteor, dt: f32) {
    for &meteor in meteors {
        if utils.vec2_dist(ship.laser_target, meteor.position) < METEOR_MINIMUM_SIZE * 4 {
            for i in 0..<VERTEX_PER_METEOR {
                r1 := meteor_get_vertice_position(meteor, i)
                r2 := meteor_get_vertice_position(meteor, (i + 1) % VERTEX_PER_METEOR)
                inter, hit := utils.segment_intersection(
                    ship.position,
                    ship.laser_target,
                    r1, 
                    r2
                )
                if hit {
                    ship.laser_target = inter
                    m1 := meteor.vertices[i]
                    m2 := meteor.vertices[(i + 1) % VERTEX_PER_METEOR]
                    m3 := meteor.vertices[(i + 2) % VERTEX_PER_METEOR]
                    m4 := meteor.vertices[((i - 1) == -1 ? VERTEX_PER_METEOR - 1 : (i - 1)) % VERTEX_PER_METEOR]
                    if m1 > MIN_RADIUS {
                        ship.stocks[meteor.material] += 0.005 * meteor.vertices[i] * dt
                        meteor.vertices[i] *= 0.995
                    }
                    if m2 > MIN_RADIUS {
                        ship.stocks[meteor.material] += 0.005 * meteor.vertices[(i + 1) % VERTEX_PER_METEOR] * dt
                        meteor.vertices[(i + 1) % VERTEX_PER_METEOR] *= 0.995
                    }
                    if m3 > MIN_RADIUS {
                        ship.stocks[meteor.material] += 0.001 * meteor.vertices[(i + 2) % VERTEX_PER_METEOR] * dt
                        meteor.vertices[(i + 2) % VERTEX_PER_METEOR] *= 0.999
                    }
                    if m4 > MIN_RADIUS {
                        ship.stocks[meteor.material] += 0.001 * meteor.vertices[((i - 1) == -1 ? VERTEX_PER_METEOR - 1 : (i - 1)) % VERTEX_PER_METEOR] * dt
                        meteor.vertices[((i - 1) == -1 ? VERTEX_PER_METEOR - 1 : (i - 1)) % VERTEX_PER_METEOR] *= 0.999
                    }
                }
            }
        }
    }
}