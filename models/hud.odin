package models

import "core:fmt"
import rl "vendor:raylib"
import "../enums"
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

hud_render :: proc(hud: Hud, level: Level) {
    hud_render_player_capacity(hud, level.ship)
    hud_render_level_info(hud, level)
    hud_render_map(hud, level)
}

hud_render_map :: proc(hud: Hud, level: Level) {
    if level.display_map {
        level_render_map(level)
    }
}

hud_render_level_info :: proc(hud: Hud, level: Level) {
    player_speed := utils.norm_vec2(level.ship.speed)
    intergrity_ratio := level.ship.integrity / level.ship.max_integrity * 100
    info_to_render := [4]cstring {
        fmt.ctprintf("Position (%.0f;%.0f)", level.ship.position.x, level.ship.position.y),
        fmt.ctprintf("Speed %.0fpx/s", utils.norm_vec2(level.ship.speed)),
        fmt.ctprintf("Sector %d", level.last_player_chunk),
        fmt.ctprintf("Integrity %.0f%%", intergrity_ratio),
    }
    color := rl.RAYWHITE
    x_padding: f32 = 5
    y_padding: f32 = 5
    for info in info_to_render {
        rl.DrawTextEx(
            hud.font, 
            info,
            [2]f32 {x_padding, y_padding},
            20, 3, color
        )
        y_padding += 20
    }
}

hud_render_player_capacity :: proc(hud: Hud, ship: Ship) {
    rl.DrawPoly([2]f32 {20, hud.height - 20}, 6, 10, 0, enums.material_color(enums.Materials.Osmium))
    rl.DrawPoly([2]f32 {20, hud.height - 50}, 6, 10, 0, enums.material_color(enums.Materials.Gold))
    rl.DrawPoly([2]f32 {20, hud.height - 80}, 6, 10, 0, enums.material_color(enums.Materials.Silver))
    rl.DrawPoly([2]f32 {20, hud.height - 110}, 6, 10, 0, enums.material_color(enums.Materials.Iron))
    rl.DrawTextEx(
        hud.font,
        fmt.ctprintf("Osmium (%.1f)", ship.stocks[enums.Materials.Osmium]),
        [2]f32 { 40, hud.height - 30 },
        20, 3, rl.RAYWHITE
    )
    rl.DrawTextEx(
        hud.font,
        fmt.ctprintf("Gold (%.1f)", ship.stocks[enums.Materials.Gold]),
        [2]f32 { 40, hud.height - 60 },
        20, 3, rl.RAYWHITE
    )
    rl.DrawTextEx(
        hud.font,
        fmt.ctprintf("Silver (%.1f)", ship.stocks[enums.Materials.Silver]),
        [2]f32 { 40, hud.height - 90 },
        20, 3, rl.RAYWHITE
    )
    rl.DrawTextEx(
        hud.font,
        fmt.ctprintf("Iron (%.1f)", ship.stocks[enums.Materials.Iron]),
        [2]f32 { 40, hud.height - 120 },
        20, 3, rl.RAYWHITE
    )
}

