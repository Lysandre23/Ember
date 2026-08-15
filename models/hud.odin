package models

import "core:fmt"
import rl "vendor:raylib"
import "../enums"

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
    hud_render_player_capacity(hud, player)
}

hud_render_player_capacity :: proc(hud: Hud, player: Player) {
    rl.DrawPoly([2]f32 {20, hud.height - 20}, 6, 10, 0, enums.material_color(enums.Materials.Osmium))
    rl.DrawPoly([2]f32 {20, hud.height - 50}, 6, 10, 0, enums.material_color(enums.Materials.Gold))
    rl.DrawPoly([2]f32 {20, hud.height - 80}, 6, 10, 0, enums.material_color(enums.Materials.Silver))
    rl.DrawPoly([2]f32 {20, hud.height - 110}, 6, 10, 0, enums.material_color(enums.Materials.Iron))
    
}