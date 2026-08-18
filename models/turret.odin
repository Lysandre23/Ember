package models

import rl "vendor:raylib"
import "core:math"
import "core:math/rand"
import "../enums"
import "../utils"

SAW_ORBIT_RADIUS    :: 55
SAW_ORBIT_SPEED     :: 3.2
SAW_HIT_RADIUS      :: 24
SAW_VISUAL_RADIUS   :: 9
SAW_TRAIL_SEGMENTS  :: 10
SAW_TRAIL_ARC       :: 1.1 // radians of comet tail behind each blade
SAW_TRAIL_THICKNESS :: 7
SAW_SPARK_CHANCE    :: 0.35

// A minigun, not a rifle: very fast/weak pulses instead of a few heavy hits
// — GUN_BASE_DAMAGE is intentionally low, the fire rate is where the power
// (and the show) comes from.
GUN_FIRE_INTERVAL   :: 0.05
GUN_RANGE           :: 550
GUN_BULLET_SPEED    :: 620
GUN_BASE_DAMAGE     :: 3
GUN_DAMAGE_STEP     :: 2
GUN_SPREAD          :: 0.7 // radians of total cone — wide on purpose, see enums/turret.odin
GUN_BULLET_LIFETIME :: 0.9
BULLET_HIT_RADIUS   :: 10

Bullet :: struct {
    position, velocity: [2]f32,
    damage: f32,
    lifetime: f32,
}

turrets_update :: proc(level: ^Level, dt: f32) {
    saw_update(level, dt)
    gun_update(level, dt)
    bullets_update(level, dt)
}

// Saws have no target selection at all — they're just a hazard ring that
// orbits the ship, on the theory that a kamikaze rushing straight at the
// player will cross it anyway. Cloning one (a shop upgrade) adds another
// blade spaced evenly around the same orbit rather than a second ring, so
// more copies means more coverage of the circle, not a thicker single hit.
saw_update :: proc(level: ^Level, dt: f32) {
    ship := &level.ship
    count := ship.turret_levels[enums.TurretType.Saw]
    if count == 0 {
        return
    }
    ship.saw_phase += SAW_ORBIT_SPEED * dt

    for i in 0..<count {
        saw_pos := saw_position(ship^, i, count)

        if rand.float32() < SAW_SPARK_CHANCE {
            particle_spawn_burst(&level.particles, saw_pos, rl.Color {255, 235, 190, 255}, 1, 1, 0.3)
        }

        for id in level.active_bots {
            bot := &level.bots.items[id]
            if bot.dead || utils.vec2_dist(bot.position, saw_pos) >= SAW_HIT_RADIUS {
                continue
            }
            // No spark burst here — bot_explode (level.odin's active_bots
            // death branch) already gives every kill, saws included, a big
            // explosion the instant it's flagged dead.
            bot.dead = true
        }
    }
}

saw_position :: proc(ship: Ship, index, count: int) -> [2]f32 {
    angle := ship.saw_phase + f32(index) * (math.TAU / f32(count))
    return ship.position + [2]f32 {math.cos(angle), math.sin(angle)} * SAW_ORBIT_RADIUS
}

// Deliberately inaccurate: GUN_SPREAD throws a wide random cone around the
// nearest target every shot instead of aiming true, so a stack of these
// reads as a chaotic spray of tracers rather than a precise turret — the
// "munitions dans tous les sens" the gun drone is supposed to feel like.
gun_update :: proc(level: ^Level, dt: f32) {
    ship := &level.ship
    gun_level := ship.turret_levels[enums.TurretType.Gun]
    if gun_level == 0 {
        return
    }

    ship.gun_reload -= dt
    if ship.gun_reload > 0 {
        return
    }

    target, found := gun_find_target(level^)
    if !found {
        return
    }
    ship.gun_reload = GUN_FIRE_INTERVAL

    base_angle := math.atan2(target.y - ship.position.y, target.x - ship.position.x)
    angle := base_angle + (rand.float32() * 2 - 1) * GUN_SPREAD * 0.5

    append(&level.bullets, Bullet {
        position = ship.position,
        velocity = [2]f32 {math.cos(angle), math.sin(angle)} * GUN_BULLET_SPEED,
        damage   = GUN_BASE_DAMAGE + f32(gun_level - 1) * GUN_DAMAGE_STEP,
        lifetime = GUN_BULLET_LIFETIME,
    })

    particle_spawn_burst(&level.particles, ship.position, enums.turret_color(enums.TurretType.Gun), 2, 2, 0.5)
}

gun_find_target :: proc(level: Level) -> (position: [2]f32, found: bool) {
    closest_dist: f32 = GUN_RANGE
    for id in level.active_bots {
        bot := level.bots.items[id]
        if bot.dead {
            continue
        }
        dist := utils.vec2_dist(bot.position, level.ship.position)
        if dist < closest_dist {
            closest_dist = dist
            position = bot.position
            found = true
        }
    }
    return
}

bullets_update :: proc(level: ^Level, dt: f32) {
    #reverse for &bullet, i in level.bullets {
        bullet.position += bullet.velocity * dt
        bullet.lifetime -= dt

        hit := false
        for id in level.active_bots {
            bot := &level.bots.items[id]
            if bot.dead || utils.vec2_dist(bot.position, bullet.position) >= BULLET_HIT_RADIUS {
                continue
            }
            bot.health -= bullet.damage
            if bot.health <= 0 {
                bot.dead = true
            }
            particle_spawn_burst(&level.particles, bullet.position, enums.turret_color(enums.TurretType.Gun), 2)
            hit = true
            break
        }

        if hit || bullet.lifetime <= 0 {
            unordered_remove(&level.bullets, i)
        }
    }
}

turrets_render :: proc(level: Level) {
    ship := level.ship
    count := ship.turret_levels[enums.TurretType.Saw]
    saw_color := enums.turret_color(enums.TurretType.Saw)

    for i in 0..<count {
        angle := ship.saw_phase + f32(i) * (math.TAU / f32(count))

        // Comet-tail trail: the motion is circular, so a straight streak
        // would look wrong — instead draw several fading ring wedges
        // following the same orbit, immediately behind the blade.
        for s in 0..<SAW_TRAIL_SEGMENTS {
            t0 := f32(s) / f32(SAW_TRAIL_SEGMENTS)
            t1 := f32(s + 1) / f32(SAW_TRAIL_SEGMENTS)
            fade := 1 - t0
            trail_color := saw_color
            trail_color.a = u8(fade * fade * 160)
            rl.DrawRing(
                ship.position,
                SAW_ORBIT_RADIUS - SAW_TRAIL_THICKNESS / 2,
                SAW_ORBIT_RADIUS + SAW_TRAIL_THICKNESS / 2,
                (angle - SAW_TRAIL_ARC * t0) * 180 / math.PI,
                (angle - SAW_TRAIL_ARC * t1) * 180 / math.PI,
                6, trail_color
            )
        }

        saw_pos := ship.position + [2]f32 {math.cos(angle), math.sin(angle)} * SAW_ORBIT_RADIUS
        rl.DrawPolyLinesEx(saw_pos, 8, SAW_VISUAL_RADIUS, angle * 180 / math.PI, 3, saw_color)
        rl.DrawCircleV(saw_pos, 3, rl.RAYWHITE)
    }

    gun_color := enums.turret_color(enums.TurretType.Gun)
    for bullet in level.bullets {
        tail := bullet.position - utils.vec2_normalize(bullet.velocity) * 16
        rl.DrawLineEx(tail, bullet.position, 3, gun_color)
        rl.DrawCircleV(bullet.position, 2.5, rl.RAYWHITE)
    }
}
