package models

import "core:fmt"
import rl "vendor:raylib"
import "../enums"
import "core:strconv"
import "../utils"

Hud :: struct {
    width, height: f32,
    font: rl.Font
}

hud_init :: proc(hud: ^Hud, width, height: i32) {
    hud.width = f32(width)
    hud.height = f32(height)
    hud.font = rl.LoadFont("../assets/font/pixel-font.otf")
    rl.GuiSetFont(hud.font)
    rl.GuiEnable()
}

hud_render :: proc(hud: Hud, player: Player) {
    hud_render_player_position(hud, player)
    hud_render_player_capacity(hud, player)
}

hud_render_player_position :: proc(hud: Hud, player: Player) {
    rl.DrawTextEx(
        hud.font, 
        fmt.ctprintf("Position (%.0f;%.0f)", player.ship.position.x, player.ship.position.y),
        [2]f32 {5, 5},
        20, 3, rl.RAYWHITE
    )
    player_speed := utils.norm_vec2(player.ship.speed)
    one_leading_zero := player_speed < 100
    two_leading_zero := player_speed < 10
    rl.DrawTextEx(
        hud.font, 
        fmt.ctprintf("Speed %s%s%.0fpx/s", one_leading_zero ? "0" : "", two_leading_zero ? "0" : "", utils.norm_vec2(player.ship.speed)),
        [2]f32 {5, 25},
        20, 3, rl.RAYWHITE
    )
}

hud_render_player_capacity :: proc(hud: Hud, player: Player) {
    rl.DrawPoly([2]f32 {20, hud.height - 20}, 6, 10, 0, enums.material_color(enums.Materials.Osmium))
    rl.DrawPoly([2]f32 {20, hud.height - 50}, 6, 10, 0, enums.material_color(enums.Materials.Gold))
    rl.DrawPoly([2]f32 {20, hud.height - 80}, 6, 10, 0, enums.material_color(enums.Materials.Silver))
    rl.DrawPoly([2]f32 {20, hud.height - 110}, 6, 10, 0, enums.material_color(enums.Materials.Iron))
    rl.DrawTextEx(
        hud.font,
        fmt.ctprintf("Osmium (%.1f)", player.ship.stocks[enums.Materials.Osmium]),
        [2]f32 { 40, hud.height - 30 },
        20, 3, rl.RAYWHITE
    )
    rl.DrawTextEx(
        hud.font,
        fmt.ctprintf("Gold (%.1f)", player.ship.stocks[enums.Materials.Gold]),
        [2]f32 { 40, hud.height - 60 },
        20, 3, rl.RAYWHITE
    )
    rl.DrawTextEx(
        hud.font,
        fmt.ctprintf("Silver (%.1f)", player.ship.stocks[enums.Materials.Silver]),
        [2]f32 { 40, hud.height - 90 },
        20, 3, rl.RAYWHITE
    )
    rl.DrawTextEx(
        hud.font,
        fmt.ctprintf("Iron (%.1f)", player.ship.stocks[enums.Materials.Iron]),
        [2]f32 { 40, hud.height - 120 },
        20, 3, rl.RAYWHITE
    )
}