package models

import "vendor:nanovg"
import rl "vendor:raylib"
import "core:math"
import "core:math/rand"
import "../enums"
import "../utils"

BOT_SPEED :: 100

Bot :: struct {
    dead: bool,
    type: enums.BotType,
    position: [2]f32,
    direction: f32
}

bot_update :: proc(bot: ^Bot, player: ^Player, dt: f32) {
    bot.direction = math.atan2(
        player.ship.position.y - bot.position.y,
        player.ship.position.x - bot.position.x,
    )
    bot.position += [2]f32 {
        BOT_SPEED * math.cos(bot.direction),
        BOT_SPEED * math.sin(bot.direction)
    } * dt
    if utils.vec2_dist(bot.position, player.ship.position) < 20 {
        player_handle_hit(player, bot.position, 3)
        bot.dead = true 
    }
}

bot_render :: proc(bot: Bot, player: Player) {
    max_dist := utils.norm_vec2([2]f32 {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())})
    if max_dist > utils.vec2_dist(bot.position, player.ship.position) {
        rl.DrawPoly(
            bot.position,
            3,
            5,
            bot.direction / math.TAU * 360,
            enums.bot_color(bot.type)
        )
    }
}