package models

import "core:fmt"
import rl "vendor:raylib"
import "../enums"
import "../utils"

Hud :: struct {
    width, height: f32,
    font: rl.Font
}

HUD_BAR_HEIGHT   :: 100
HUD_PADDING      :: 14
HUD_SECTION_GAP  :: 28
HUD_BG_COLOR     :: rl.Color { 10, 10, 16, 235 }
HUD_BORDER_COLOR :: rl.Color { 255, 255, 255, 45 }
HUD_TEXT_COLOR   :: rl.Color { 225, 225, 235, 255 }
HUD_LABEL_COLOR  :: rl.Color { 140, 140, 155, 255 }

hud_init :: proc(hud: ^Hud, width, height: i32) {
    hud.width = f32(width)
    hud.height = f32(height)
    hud.font = rl.LoadFont("../assets/fonts/pixel-font.otf")
    if hud.font.texture.id == 0 {
        hud.font = rl.GetFontDefault()
    }
    rl.GuiSetFont(hud.font)
    rl.GuiEnable()
}

hud_render :: proc(hud: Hud, level: ^Level) {
    if level.extract_open {
        extract_render(hud, level)
    } else if level.shop_open {
        shop_render(hud, level)
    } else if level.display_map {
        level_render_map(hud, level^)
    } else {
        hud_render_bar(hud, level^)
    }
}

hud_render_bar :: proc(hud: Hud, level: Level) {
    bar_y := hud.height - HUD_BAR_HEIGHT

    rl.DrawRectangleRec(rl.Rectangle { 0, bar_y, hud.width, HUD_BAR_HEIGHT }, HUD_BG_COLOR)
    rl.DrawRectangleRec(rl.Rectangle { 0, bar_y, hud.width, 2 }, HUD_BORDER_COLOR)

    cursor_x : f32 = HUD_PADDING
    cursor_x = hud_render_bar_stats(hud, level, cursor_x, bar_y)

    cursor_x += HUD_SECTION_GAP
    hud_draw_divider(bar_y, cursor_x)
    cursor_x += HUD_SECTION_GAP

    cursor_x = hud_render_bar_cargo(hud, level.ship, cursor_x, bar_y)

    minimap_size : f32 = HUD_BAR_HEIGHT - HUD_PADDING * 2
    minimap_origin := [2]f32 { hud.width - HUD_PADDING - minimap_size, bar_y + HUD_PADDING }
    hud_draw_divider(bar_y, minimap_origin.x - HUD_SECTION_GAP)
    level_render_minimap(hud, level, minimap_origin, minimap_size)
    extract_render_compass(hud, level, minimap_origin, minimap_size)
}

hud_draw_divider :: proc(bar_y, x: f32) {
    rl.DrawLineEx(
        [2]f32 { x, bar_y + HUD_PADDING },
        [2]f32 { x, bar_y + HUD_BAR_HEIGHT - HUD_PADDING },
        1, rl.Color { 255, 255, 255, 30 }
    )
}

hud_render_bar_stats :: proc(hud: Hud, level: Level, start_x, bar_y: f32) -> f32 {
    x := start_x
    gap : f32 = HUD_SECTION_GAP * 0.7

    x += hud_draw_stat(hud, x, bar_y, "MAP", fmt.ctprintf("%d", level.map_tier)) + gap
    x += hud_draw_stat(hud, x, bar_y, "SECTOR", fmt.ctprintf("%d", level.last_player_chunk)) + gap
    x += hud_draw_stat(hud, x, bar_y, "SPEED", fmt.ctprintf("%.0f px/s", utils.norm_vec2(level.ship.speed))) + gap

    integrity_ratio := level.ship.integrity / level.ship.max_integrity
    fuel_ratio := level.ship.fuel / level.ship.max_fuel
    energy_ratio := level.ship.laser_energy / level.ship.max_laser_energy

    x += hud_draw_bar_stat(hud, x, bar_y, "HULL", integrity_ratio, hud_integrity_color(integrity_ratio)) + gap
    x += hud_draw_bar_stat(hud, x, bar_y, "FUEL", fuel_ratio, rl.Color { 100, 200, 255, 255 }) + gap
    x += hud_draw_bar_stat(hud, x, bar_y, "ENERGY", energy_ratio, rl.Color { 190, 120, 255, 255 })

    return x
}

hud_draw_bar_stat :: proc(hud: Hud, x, bar_y: f32, label: cstring, ratio: f32, color: rl.Color) -> f32 {
    label_y := bar_y + HUD_BAR_HEIGHT / 2 - 16
    fill_y := bar_y + HUD_BAR_HEIGHT / 2 + 3
    bar_w : f32 = 88
    bar_h : f32 = 9

    rl.DrawTextEx(hud.font, label, [2]f32 { x, label_y }, 11, 1, HUD_LABEL_COLOR)
    rl.DrawRectangleRounded(rl.Rectangle { x, fill_y, bar_w, bar_h }, 0.5, 4, rl.Color { 255, 255, 255, 25 })
    rl.DrawRectangleRounded(rl.Rectangle { x, fill_y, bar_w * clamp(ratio, 0, 1), bar_h }, 0.5, 4, color)

    return bar_w
}

hud_draw_stat :: proc(hud: Hud, x, bar_y: f32, label, value: cstring) -> f32 {
    label_y := bar_y + HUD_BAR_HEIGHT / 2 - 16
    value_y := bar_y + HUD_BAR_HEIGHT / 2 + 1
    label_size : f32 = 11
    value_size : f32 = 17

    rl.DrawTextEx(hud.font, label, [2]f32 { x, label_y }, label_size, 1, HUD_LABEL_COLOR)
    rl.DrawTextEx(hud.font, value, [2]f32 { x, value_y }, value_size, 1, HUD_TEXT_COLOR)

    label_w := rl.MeasureTextEx(hud.font, label, label_size, 1).x
    value_w := rl.MeasureTextEx(hud.font, value, value_size, 1).x
    return max(label_w, value_w)
}

hud_integrity_color :: proc(ratio: f32) -> rl.Color {
    if ratio > 0.6 {
        return rl.Color { 46, 204, 113, 255 }
    }
    if ratio > 0.3 {
        return rl.Color { 241, 196, 15, 255 }
    }
    return rl.Color { 231, 76, 60, 255 }
}

hud_render_bar_cargo :: proc(hud: Hud, ship: Ship, start_x, bar_y: f32) -> f32 {
    materials := [4]enums.Materials {
        enums.Materials.Osmium, enums.Materials.Gold,
        enums.Materials.Silver, enums.Materials.Iron,
    }

    x := start_x
    gap : f32 = HUD_SECTION_GAP * 0.7
    icon_r : f32 = 8
    center_y := bar_y + HUD_BAR_HEIGHT / 2

    for material in materials {
        rl.DrawPoly([2]f32 { x + icon_r, center_y }, 6, icon_r, 0, enums.material_color(material))

        text := fmt.ctprintf("%.1f", ship.stocks[material])
        text_x := x + icon_r * 2 + 8
        rl.DrawTextEx(hud.font, text, [2]f32 { text_x, center_y - 9 }, 17, 1, HUD_TEXT_COLOR)

        x = text_x + rl.MeasureTextEx(hud.font, text, 17, 1).x + gap
    }

    return x
}
