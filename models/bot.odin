package models

import "vendor:nanovg"
import rl "vendor:raylib"
import "core:math"
import "core:math/rand"
import "../enums"
import "../utils"

BOT_SPEED :: 150

EXPLOSION_PARTICLE_COUNT :: 16
EXPLOSION_FLASH_COUNT    :: 6
SHAKE_PER_KILL :: 2.2
SHAKE_MAX      :: 10.0
SHAKE_DECAY    :: 18.0 // per second

// Sniper bots hold a standoff range instead of closing in — SNIPER_SPEED is
// their reposition speed (slower than a kamikaze's straight-line rush, since
// they're relocating rather than committing to a charge), SNIPER_IDEAL_RANGE
// is the distance they try to hold, and SNIPER_RANGE_BAND is the dead zone
// around it so they don't jitter in and out every frame. Once inside the
// band they strafe sideways instead of standing still, which is what reads
// as "tenacious" rather than passive.
SNIPER_SPEED                  :: 90
SNIPER_STRAFE_SPEED           :: 60
SNIPER_IDEAL_RANGE            :: 380
SNIPER_RANGE_BAND             :: 60
// Deliberately far slower than the player's minigun (GUN_FIRE_INTERVAL,
// models/turret.odin) — a sniper fires a few heavy, telegraphed shots
// instead of a stream. The random variance keeps a pack of snipers from
// clicking their shots in perfect unison.
SNIPER_FIRE_INTERVAL          :: 1.7
SNIPER_FIRE_INTERVAL_VARIANCE :: 0.4
SNIPER_BULLET_SPEED           :: 520
SNIPER_BULLET_DAMAGE          :: 9
SNIPER_BULLET_LIFETIME        :: 1.6

// Bots try to route around meteors instead of plowing straight through them:
// BOT_METEOR_LOOKAHEAD is how far ahead they start reacting, BOT_METEOR_MARGIN
// is the extra clearance kept beyond a meteor's own avoid_radius, and
// BOT_METEOR_AVOID_GAIN is how hard the steering pulls off course. A bot that
// still ends up hitting one anyway is destroyed and chips the meteor for
// BOT_METEOR_IMPACT_DAMAGE — well above CELL_MAX_HP so it always kills the
// cell it hits outright rather than just chipping it (see meteor.odin).
BOT_METEOR_LOOKAHEAD     :: 140
BOT_METEOR_MARGIN        :: 22
BOT_METEOR_AVOID_GAIN    :: 1.6
BOT_METEOR_IMPACT_DAMAGE :: 10

// How much stronger each subsequent map's bots are than the last —
// level.map_tier increments via level_advance_map (level.odin) each time the
// player takes an extraction point, so a bot's health (level_spawn_bot) and
// weapons (sniper_update's bullet, kamikaze_update's ram) scale up gently
// rather than jumping straight back to full swarm pressure on a fresh map.
BOT_TIER_HEALTH_MULT :: 0.15
BOT_TIER_DAMAGE_MULT :: 0.12

bot_tier_multiplier :: proc(level: Level, mult_per_tier: f32) -> f32 {
    return 1 + f32(level.map_tier - 1) * mult_per_tier
}

Bot :: struct {
    dead: bool,
    type: enums.BotType,
    position: [2]f32,
    direction: f32,
    health: f32,

    // Sniper-only state (models/bot.odin:sniper_update). Unused by other
    // bot types.
    fire_reload: f32,
    strafe_sign: f32,
}

bot_update :: proc(bot: ^Bot, level: ^Level, dt: f32) {
    if bot.dead {
        return
    }
    switch bot.type {
        case enums.BotType.Kamikaze: kamikaze_update(bot, level, dt)
        case enums.BotType.Sniper: sniper_update(bot, level, dt)
    }
}

// Steers `desired_dir` (a unit vector) away from any meteor within
// BOT_METEOR_LOOKAHEAD of `position` that's roughly ahead of travel, so a
// bot flows around a rock instead of walking straight into it. Meteors
// behind the direction of travel are ignored so a bot doesn't swerve away
// from something it's already past. Falls back to desired_dir unchanged when
// nothing nearby needs avoiding.
bot_steer_around_meteors :: proc(level: Level, position, desired_dir: [2]f32) -> [2]f32 {
    push: [2]f32
    for id in level.active_meteors {
        meteor := level.meteors.items[id]
        to_meteor := meteor.position - position
        dist := utils.norm_vec2(to_meteor)
        safe := meteor.avoid_radius + BOT_METEOR_MARGIN
        if dist >= safe + BOT_METEOR_LOOKAHEAD {
            continue
        }
        if dist > 0.01 {
            ahead := (to_meteor.x * desired_dir.x + to_meteor.y * desired_dir.y) / dist
            if ahead < 0 {
                continue
            }
        }
        away := dist > 0.01 ? -to_meteor / dist : [2]f32 {1, 0}
        weight := 1 - clamp((dist - safe) / BOT_METEOR_LOOKAHEAD, 0, 1)
        push += away * weight
    }
    if utils.norm_vec2(push) < 0.01 {
        return desired_dir
    }
    return utils.vec2_normalize(desired_dir + push * BOT_METEOR_AVOID_GAIN)
}

// Resolves an actual meteor collision along the prev->new movement segment —
// steering wasn't enough to dodge it. The bot doesn't survive impact, but
// the meteor takes a real hit (level_meteor_impact), same as if the ship's
// laser had clipped it.
bot_resolve_meteor_collision :: proc(level: ^Level, prev, new: [2]f32) -> bool {
    impact, material, hit := level_meteor_impact(level, prev, new, BOT_METEOR_IMPACT_DAMAGE)
    if hit {
        particle_spawn_burst(&level.particles, impact, enums.material_color(material), 8, 2, 0.6)
    }
    return hit
}

// Rushes the ship, steering around meteors in its path. bot.direction
// tracks the actual (possibly curved) movement direction rather than the
// raw bearing to the ship, so its nose visibly points where it's going —
// swerving around a rock reads as a swerve, not a rigid beeline with a body
// that stays locked on the ship regardless.
kamikaze_update :: proc(bot: ^Bot, level: ^Level, dt: f32) {
    ship := &level.ship
    to_ship_dir := math.atan2(ship.position.y - bot.position.y, ship.position.x - bot.position.x)
    desired := [2]f32 {math.cos(to_ship_dir), math.sin(to_ship_dir)}
    move_dir := bot_steer_around_meteors(level^, bot.position, desired)
    bot.direction = math.atan2(move_dir.y, move_dir.x)

    prev := bot.position
    bot.position += move_dir * BOT_SPEED * dt

    if bot_resolve_meteor_collision(level, prev, bot.position) {
        bot.dead = true
        return
    }

    if utils.vec2_dist(bot.position, ship.position) < SHIP_HIT_RADIUS {
        ship_handle_hit(ship, bot.position, 3 * bot_tier_multiplier(level^, BOT_TIER_DAMAGE_MULT))
        bot.dead = true
    }
}

// Holds SNIPER_IDEAL_RANGE from the ship — closing in when too far, backing
// off when too close, strafing sideways once in the band — while firing slow,
// heavy shots, and steering around meteors the same way kamikaze_update does.
// bot.direction always points at the ship (used both for aim and for
// rendering the barrel in bot_render) independent of the movement direction,
// so it can retreat/strafe around a rock while still facing and shooting at
// its target.
sniper_update :: proc(bot: ^Bot, level: ^Level, dt: f32) {
    ship := &level.ship
    to_ship := ship.position - bot.position
    dist := utils.norm_vec2(to_ship)
    bot.direction = math.atan2(to_ship.y, to_ship.x)
    aim := [2]f32 { math.cos(bot.direction), math.sin(bot.direction) }

    desired: [2]f32
    speed: f32
    if dist < SNIPER_IDEAL_RANGE - SNIPER_RANGE_BAND {
        desired = -aim
        speed = SNIPER_SPEED
    } else if dist > SNIPER_IDEAL_RANGE + SNIPER_RANGE_BAND {
        desired = aim
        speed = SNIPER_SPEED
    } else {
        desired = [2]f32 { -aim.y, aim.x } * bot.strafe_sign
        speed = SNIPER_STRAFE_SPEED
    }
    move_dir := bot_steer_around_meteors(level^, bot.position, desired)

    prev := bot.position
    bot.position += move_dir * speed * dt

    if bot_resolve_meteor_collision(level, prev, bot.position) {
        bot.dead = true
        return
    }

    bot.fire_reload -= dt
    if bot.fire_reload <= 0 && dist < SNIPER_IDEAL_RANGE + SNIPER_RANGE_BAND * 2 {
        bot.fire_reload = SNIPER_FIRE_INTERVAL + (rand.float32() * 2 - 1) * SNIPER_FIRE_INTERVAL_VARIANCE
        append(&level.enemy_bullets, Bullet {
            position = bot.position,
            velocity = aim * SNIPER_BULLET_SPEED,
            damage   = SNIPER_BULLET_DAMAGE * bot_tier_multiplier(level^, BOT_TIER_DAMAGE_MULT),
            lifetime = SNIPER_BULLET_LIFETIME,
        })
        particle_spawn_burst(&level.particles, bot.position, enums.bot_color(bot.type), 3, 2, 0.4)
    }
}

// Enemy fire (currently only snipers) reuses turret.odin's Bullet shape but
// is tracked separately from level.bullets, since those check collision
// against bots and these check collision against the ship.
enemy_bullets_update :: proc(level: ^Level, dt: f32) {
    ship := &level.ship
    #reverse for &bullet, i in level.enemy_bullets {
        bullet.position += bullet.velocity * dt
        bullet.lifetime -= dt

        hit := false
        if utils.vec2_dist(bullet.position, ship.position) < SHIP_HIT_RADIUS {
            ship_take_damage(ship, bullet.damage)
            particle_spawn_burst(&level.particles, bullet.position, enums.bot_color(enums.BotType.Sniper), 3)
            hit = true
        } else if level_point_in_any_meteor(level^, bullet.position) {
            // A meteor blocks the shot — the player can duck behind rock to
            // dodge sniper fire.
            particle_spawn_burst(&level.particles, bullet.position, rl.Color {170, 170, 180, 255}, 3)
            hit = true
        }

        if hit || bullet.lifetime <= 0 {
            unordered_remove(&level.enemy_bullets, i)
        }
    }
}

enemy_bullets_render :: proc(bullets: [dynamic]Bullet) {
    color := enums.bot_color(enums.BotType.Sniper)
    for bullet in bullets {
        tail := bullet.position - utils.vec2_normalize(bullet.velocity) * 14
        rl.DrawLineEx(tail, bullet.position, 2, color)
        rl.DrawCircleV(bullet.position, 2, rl.RAYWHITE)
    }
}

// The single place a bot's death actually reads as an event, regardless of
// what killed it (laser, saw, gun bullet, or ramming the ship itself) — see
// the death branch of level_update's active_bots loop, the one spot every
// kill path funnels through before the bot's slot is freed.
bot_explode :: proc(level: ^Level, position: [2]f32, bot_type: enums.BotType) {
    particle_spawn_burst(&level.particles, position, enums.bot_color(bot_type), EXPLOSION_PARTICLE_COUNT, 2, 0.5)
    particle_spawn_burst(&level.particles, position, rl.RAYWHITE, EXPLOSION_FLASH_COUNT, 3, 0.5)
    level.camera_shake = min(SHAKE_MAX, level.camera_shake + SHAKE_PER_KILL)
}

bot_render :: proc(bot: Bot, ship: Ship) {
    max_dist := utils.norm_vec2([2]f32 {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())})
    if max_dist <= utils.vec2_dist(bot.position, ship.position) {
        return
    }

    color := enums.bot_color(bot.type)
    switch bot.type {
        case enums.BotType.Kamikaze:
            rl.DrawPoly(bot.position, 3, 5, bot.direction / math.TAU * 360, color)
        case enums.BotType.Sniper:
            // Diamond body plus a barrel line along the aim direction, so a
            // sniper reads as a stationary-ish gun emplacement rather than a
            // rushing triangle even at a glance.
            rl.DrawPoly(bot.position, 4, 7, bot.direction / math.TAU * 360, color)
            barrel_end := bot.position + [2]f32 {math.cos(bot.direction), math.sin(bot.direction)} * 13
            rl.DrawLineEx(bot.position, barrel_end, 2, color)
    }
}