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

Bot :: struct {
    dead: bool,
    type: enums.BotType,
    position: [2]f32,
    direction: f32,
    health: f32,
}

bot_update :: proc(bot: ^Bot, ship: ^Ship, dt: f32) {
    if bot.dead {
        return
    }
    bot.direction = math.atan2(
        ship.position.y - bot.position.y,
        ship.position.x - bot.position.x,
    )
    bot.position += [2]f32 {
        BOT_SPEED * math.cos(bot.direction),
        BOT_SPEED * math.sin(bot.direction)
    } * dt
    if utils.vec2_dist(bot.position, ship.position) < 20 {
        ship_handle_hit(ship, bot.position, 3)
        bot.dead = true 
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
    if max_dist > utils.vec2_dist(bot.position, ship.position) {
        rl.DrawPoly(
            bot.position,
            3,
            5,
            bot.direction / math.TAU * 360,
            enums.bot_color(bot.type)
        )
    }
}