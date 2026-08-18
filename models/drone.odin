package models

import rl "vendor:raylib"
import "core:math"
import "../enums"
import "../utils"

// The strike drone is bought and leveled up at a shop like Saw/Gun (see
// shop.odin's PURCHASABLE_TURRETS) — each level adds another drone, the same
// way saw_update grows blade count with level, rather than making a single
// drone individually stronger. Each drone has two modes: with no bot in
// range it idles behind the ship like a following companion; the moment a
// bot enters DRONE_ENGAGE_RANGE of the ship it snaps into "flash arrow"
// mode, dashing at very high speed to the nearest live bot, hitting it, and
// immediately retargeting the next nearest — it never dies and never
// lingers on one target.
DRONE_FOLLOW_OFFSET  :: 50
DRONE_FOLLOW_LERP    :: 6.0
DRONE_STRIKE_SPEED   :: 1000
DRONE_HIT_RADIUS     :: 16
DRONE_DAMAGE         :: 60
DRONE_TRAIL_SEGMENTS :: 6
DRONE_VISUAL_LENGTH  :: 14
DRONE_VISUAL_WIDTH   :: 6

// MomentumCells boost (enums.BoostType): every drone hit trickles a little
// fuel back — meant to combo with StarvedEdge (ship.odin), which scales
// laser damage off the fuel gauge, so investing in strike drones can
// directly sustain laser output instead of the two being unrelated systems.
DRONE_FUEL_GAIN :: 3

// A bot has to be within this distance of the ship (not of the drone) to be
// engaged at all, so a drone chasing a bot never chains itself out past
// what's roughly visible on screen.
DRONE_ENGAGE_RANGE :: 420

Drone :: struct {
    position: [2]f32,
    angle: f32,
    target_id: int,
    striking: bool,
    trail: [DRONE_TRAIL_SEGMENTS][2]f32,
}

// Drones pick targets one at a time, each excluding whatever the
// earlier-processed drones already claimed this same frame (`claimed`) —
// without that, every drone independently computes "nearest bot" from
// roughly the same position (they idle clustered right behind the ship) and
// all converge on the exact same target, making extra drones pointless.
// Target selection is recomputed fresh every frame rather than being a
// persistent lock-on, so this reshuffles naturally as bots die or get closer.
drone_update :: proc(level: ^Level, dt: f32) {
    count := level.ship.turret_levels[enums.TurretType.Strike]
    claimed: [TURRET_MAX_LEVEL]int
    for i in 0..<count {
        claimed[i] = drone_update_one(&level.drones[i], level, i, count, claimed[:i], dt)
    }
}

drone_update_one :: proc(drone: ^Drone, level: ^Level, index, count: int, claimed: []int, dt: f32) -> int {
    ship := &level.ship
    prev := drone.position

    for i := DRONE_TRAIL_SEGMENTS - 1; i > 0; i -= 1 {
        drone.trail[i] = drone.trail[i - 1]
    }
    drone.trail[0] = drone.position

    target_id, target_pos, found := drone_find_nearest_bot(level^, drone.position, ship.position, DRONE_ENGAGE_RANGE, claimed)

    if !found {
        drone.striking = false
        drone.target_id = -1

        follow := drone_follow_position(ship^, index, count)
        t := 1 - math.exp(-DRONE_FOLLOW_LERP * dt)
        drone.position = utils.vec2_lerp(drone.position, follow, t)

        to_ship := ship.position - drone.position
        if utils.norm_vec2(to_ship) > 1 {
            drone.angle = math.atan2(to_ship.y, to_ship.x)
        }
    } else {
        drone.striking = true
        drone.target_id = target_id

        to_target := target_pos - drone.position
        dist := utils.norm_vec2(to_target)
        drone.angle = math.atan2(to_target.y, to_target.x)

        if dist < DRONE_HIT_RADIUS {
            bot := &level.bots.items[target_id]
            bot.health -= DRONE_DAMAGE
            particle_spawn_burst(&level.particles, bot.position, enums.turret_color(enums.TurretType.Strike), 6, 2, 0.5)
            if bot.health <= 0 {
                bot.dead = true
            }
            if enums.BoostType.MomentumCells in ship.boosts {
                ship.fuel = min(ship.max_fuel, ship.fuel + DRONE_FUEL_GAIN)
            }
        } else {
            dir := to_target / dist
            drone.position += dir * DRONE_STRIKE_SPEED * dt
        }
    }

    drone_mine_meteors(level, prev, drone.position)

    return found ? target_id : -1
}

// Unlike a bot's ram, the strike drone is unbreakable — passing through a
// meteor just mines it (level_meteor_impact, the same swept-segment rule the
// ship's laser uses) instead of destroying the drone. At the drone's speed a
// single pass crosses several cells over consecutive frames, which is what
// reads as "the arrow cuts the meteor in two" when it goes through the
// middle.
DRONE_METEOR_DAMAGE :: 12

drone_mine_meteors :: proc(level: ^Level, prev, new: [2]f32) {
    impact, material, hit := level_meteor_impact(level, prev, new, DRONE_METEOR_DAMAGE)
    if hit {
        particle_spawn_burst(&level.particles, impact, enums.material_color(material), 4, 2, 0.4)
    }
}

// Idle position behind the ship. With more than one drone owned, they fan
// out around that point instead of stacking on top of each other.
drone_follow_position :: proc(ship: Ship, index, count: int) -> [2]f32 {
    if count <= 1 {
        return ship.position - [2]f32 {math.cos(ship.direction), math.sin(ship.direction)} * DRONE_FOLLOW_OFFSET
    }
    spread := (f32(index) - f32(count - 1) / 2) * 0.5
    angle := ship.direction + math.PI + spread
    return ship.position + [2]f32 {math.cos(angle), math.sin(angle)} * DRONE_FOLLOW_OFFSET
}

// Nearest live bot to `from`, restricted to bots within max_range of
// ship_position (the gate that keeps a drone from being sent chasing
// something off screen) and excluding any id already in `claimed` (another
// drone's pick this frame — see drone_update).
drone_find_nearest_bot :: proc(level: Level, from, ship_position: [2]f32, max_range: f32, claimed: []int) -> (id: int, position: [2]f32, found: bool) {
    closest_dist := f32(1e9)
    bot_loop: for bot_id in level.active_bots {
        bot := level.bots.items[bot_id]
        if bot.dead {
            continue
        }
        for c in claimed {
            if c == bot_id {
                continue bot_loop
            }
        }
        if utils.vec2_dist(bot.position, ship_position) > max_range {
            continue
        }
        dist := utils.vec2_dist(bot.position, from)
        if dist < closest_dist {
            closest_dist = dist
            id = bot_id
            position = bot.position
            found = true
        }
    }
    return
}

drone_render :: proc(level: Level) {
    count := level.ship.turret_levels[enums.TurretType.Strike]
    for i in 0..<count {
        drone_render_one(level, level.drones[i])
    }
}

drone_render_one :: proc(level: Level, drone: Drone) {
    color := enums.turret_color(enums.TurretType.Strike)

    for i in 0..<DRONE_TRAIL_SEGMENTS {
        fade := 1 - f32(i) / f32(DRONE_TRAIL_SEGMENTS)
        trail_color := color
        trail_color.a = u8(fade * fade * 180)
        rl.DrawCircleV(drone.trail[i], DRONE_VISUAL_WIDTH * 0.5 * fade, trail_color)
    }

    if drone.striking && drone.target_id >= 0 && drone.target_id < len(level.bots.items) {
        target := level.bots.items[drone.target_id]
        if !target.dead {
            flash_color := color
            flash_color.a = 90
            rl.DrawLineEx(drone.position, target.position, 1.5, flash_color)
        }
    }

    tip := drone.position + [2]f32 {math.cos(drone.angle), math.sin(drone.angle)} * DRONE_VISUAL_LENGTH
    back_l := drone.position + utils.rotate_vec2_around([2]f32 {-DRONE_VISUAL_LENGTH * 0.6, -DRONE_VISUAL_WIDTH}, {0, 0}, drone.angle)
    back_r := drone.position + utils.rotate_vec2_around([2]f32 {-DRONE_VISUAL_LENGTH * 0.6, DRONE_VISUAL_WIDTH}, {0, 0}, drone.angle)
    rl.DrawTriangle(tip, back_l, back_r, color)
    rl.DrawCircleV(drone.position, 2, rl.RAYWHITE)
}
