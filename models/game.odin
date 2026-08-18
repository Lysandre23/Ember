package models

import "core:fmt"
import rl "vendor:raylib"
import "../enums"
import "../utils"

Game :: struct {
    state: enums.GameState,
    level: Level,
    width, height: i32,
    background: Background,
    hud: Hud,
    crt_shader: rl.Shader,
    scene_target: rl.RenderTexture2D,

    // Deepest map tier ever reached, across every run this executable has
    // seen — loaded from disk at startup (save.odin) and re-persisted the
    // instant a run beats it (game_update). Shown on the main menu.
    best_score: int,

    // Set by the Quit button on the main menu (game_render_menu) — checked
    // by game_run's loop condition alongside rl.WindowShouldClose().
    should_quit: bool,
}

// Scanline darkening and neon glow strength for utils.CRT_SHADER — kept
// modest on purpose per design direction ("not too much").
CRT_SCANLINE_INTENSITY :: 0.15
CRT_LINE_SPACING       :: 3.0
CRT_GLOW_INTENSITY     :: 0.35
CRT_GLOW_THRESHOLD     :: 0.6

game_init :: proc(game: ^Game) {
    rl.SetConfigFlags(rl.ConfigFlags { .MSAA_4X_HINT })
    rl.InitWindow(rl.GetScreenWidth(), rl.GetScreenHeight(), "Ember")
    game.state = enums.GameState.Menu
    game.width = 10000
    game.height = 10000
    game.best_score = save_load_best_score()
    // No level yet — game_start_run builds one the moment the player
    // actually presses Play, not before.
    background_init(&game.background, game.width, game.height)
    hud_init(&game.hud, rl.GetScreenWidth(), rl.GetScreenHeight())
    game_init_shader(game)
    rl.SetTargetFPS(180)
}

// Builds a fresh run from scratch: a new ship at map_tier 1. Used both by
// the main menu's Play button and by ENTER on the Death screen (game_update)
// — everything about whatever map existed before (meteors, bots, POIs) is
// torn down and rebuilt by level_reset the same way a normal extraction jump
// is, just with a brand new ship instead of the previous one carried over.
game_start_run :: proc(game: ^Game) {
    // Unlike level_advance_map (which carries the same ship, and therefore
    // the same stocks map/trail_particles allocations, forward), this
    // discards any previous ship entirely for a brand new one — free what it
    // owned before level_reset's zero-value overwrite drops the only
    // reference to them. Safe to call even when there was no previous run
    // (game.level.ship is still zero-valued): delete on a nil map/dynamic
    // array is a no-op.
    delete(game.level.ship.stocks)
    delete(game.level.ship.trail_particles)
    level_reset(&game.level, ship_create(), 1)
    game.state = enums.GameState.Run
}

game_init_shader :: proc(game: ^Game) {
    game.crt_shader = rl.LoadShaderFromMemory(nil, utils.CRT_SHADER)
    game.scene_target = rl.LoadRenderTexture(rl.GetScreenWidth(), rl.GetScreenHeight())

    screen_w := f32(rl.GetScreenWidth())
    screen_h := f32(rl.GetScreenHeight())
    intensity := f32(CRT_SCANLINE_INTENSITY)
    line_spacing := f32(CRT_LINE_SPACING)
    glow_intensity := f32(CRT_GLOW_INTENSITY)
    glow_threshold := f32(CRT_GLOW_THRESHOLD)

    rl.SetShaderValue(game.crt_shader, rl.GetShaderLocation(game.crt_shader, "screenWidth"), &screen_w, .FLOAT)
    rl.SetShaderValue(game.crt_shader, rl.GetShaderLocation(game.crt_shader, "screenHeight"), &screen_h, .FLOAT)
    rl.SetShaderValue(game.crt_shader, rl.GetShaderLocation(game.crt_shader, "intensity"), &intensity, .FLOAT)
    rl.SetShaderValue(game.crt_shader, rl.GetShaderLocation(game.crt_shader, "lineSpacing"), &line_spacing, .FLOAT)
    rl.SetShaderValue(game.crt_shader, rl.GetShaderLocation(game.crt_shader, "glowIntensity"), &glow_intensity, .FLOAT)
    rl.SetShaderValue(game.crt_shader, rl.GetShaderLocation(game.crt_shader, "glowThreshold"), &glow_threshold, .FLOAT)
}

game_run :: proc(game: ^Game) {
    rl.SetMouseCursor(.CROSSHAIR)
    for !rl.WindowShouldClose() && !game.should_quit {
        game_update(game, rl.GetFrameTime())

        // The whole frame is rendered to an offscreen texture first, then
        // drawn to the screen through the CRT shader in a single pass — that
        // way scanlines/glow apply uniformly to the world and the HUD alike.
        rl.BeginTextureMode(game.scene_target)
        rl.ClearBackground(rl.BLACK)
        game_render(game)
        rl.EndTextureMode()

        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        rl.BeginShaderMode(game.crt_shader)
        rl.DrawTextureRec(
            game.scene_target.texture,
            rl.Rectangle {0, 0, f32(game.scene_target.texture.width), -f32(game.scene_target.texture.height)},
            {0, 0}, rl.WHITE,
        )
        rl.EndShaderMode()
        rl.EndDrawing()
    }
    rl.UnloadShader(game.crt_shader)
    rl.UnloadRenderTexture(game.scene_target)
    rl.CloseWindow()
}

game_update :: proc(game: ^Game, dt: f32) {
    if game.state == enums.GameState.Run {
        level_update(&game.level, dt)

        if game.level.map_tier > game.best_score {
            game.best_score = game.level.map_tier
            save_write_best_score(game.best_score)
        }

        if game.level.ship.integrity <= 0 {
            game.state = enums.GameState.Death
        }
    } else if game.state == enums.GameState.Death {
        if rl.IsKeyPressed(.ENTER) {
            game_start_run(game)
        }
    }
}

game_render :: proc(game: ^Game) {
    if game.state == enums.GameState.Menu {
        game_render_menu(game)
    } else if game.state == enums.GameState.Run || game.state == enums.GameState.Death {
        rl.BeginMode2D(game.level.camera)
        game_render_run(game)
        rl.EndMode2D()
        hud_render(game.hud, &game.level)

        if game.state == enums.GameState.Death {
            game_render_death(game.hud, game.level, game.best_score)
        }
    }
}

// Immediate-mode, same click-handling style as shop_render/extract_render —
// only ever drawn while game.state is Menu, so a click here can't leak
// through to anything else.
game_render_menu :: proc(game: ^Game) {
    hud := game.hud
    mouse := rl.GetMousePosition()
    clicked := rl.IsMouseButtonPressed(.LEFT)

    rl.DrawRectangleRec(rl.Rectangle {0, 0, hud.width, hud.height}, rl.Color {6, 6, 10, 255})

    title: cstring = "EMBER"
    title_size : f32 = 48
    title_w := rl.MeasureTextEx(hud.font, title, title_size, 2).x
    title_y := hud.height * 0.28
    rl.DrawTextEx(hud.font, title, [2]f32 {(hud.width - title_w) / 2, title_y}, title_size, 2, rl.RAYWHITE)

    best_text := fmt.ctprintf("Best run: Map %d", game.best_score)
    best_w := rl.MeasureTextEx(hud.font, best_text, 16, 1).x
    rl.DrawTextEx(hud.font, best_text, [2]f32 {(hud.width - best_w) / 2, title_y + 62}, 16, 1, HUD_LABEL_COLOR)

    button_w : f32 = 220
    button_h : f32 = 46
    button_x := (hud.width - button_w) / 2
    play_bounds := rl.Rectangle {button_x, hud.height * 0.55, button_w, button_h}
    quit_bounds := rl.Rectangle {button_x, hud.height * 0.55 + button_h + 16, button_w, button_h}

    if shop_button(hud, play_bounds, "Play", true, mouse, clicked) || rl.IsKeyPressed(.ENTER) {
        game_start_run(game)
    }
    if shop_button(hud, quit_bounds, "Quit", true, mouse, clicked) {
        game.should_quit = true
    }
}

game_render_run :: proc(game: ^Game) {
    background_render(game.background, game.level.ship)
    level_render(&game.level)
}

// Drawn on top of the frozen last frame of the run (level_update stops being
// called the instant integrity hits 0, so nothing moves underneath).
game_render_death :: proc(hud: Hud, level: Level, best_score: int) {
    rl.DrawRectangleRec(rl.Rectangle {0, 0, hud.width, hud.height}, rl.Color {4, 4, 8, 230})

    panel_w : f32 = min(hud.width - 80, 480)
    panel_h : f32 = 200
    panel_x := (hud.width - panel_w) / 2
    panel_y := (hud.height - panel_h) / 2
    panel := rl.Rectangle {panel_x, panel_y, panel_w, panel_h}

    rl.DrawRectangleRounded(panel, 0.05, 8, rl.Color {14, 14, 20, 250})
    rl.DrawRectangleRoundedLinesEx(panel, 0.05, 8, 1.5, rl.Color {231, 76, 60, 160})

    rl.DrawTextEx(hud.font, "HULL BREACHED", [2]f32 {panel_x + 24, panel_y + 20}, 24, 1, rl.Color {231, 76, 60, 255})

    stats := fmt.ctprintf("Reached Map %d", level.map_tier)
    rl.DrawTextEx(hud.font, stats, [2]f32 {panel_x + 24, panel_y + 62}, 15, 1, HUD_TEXT_COLOR)

    // game_update saves best_score the instant map_tier passes it, so
    // reaching it exactly this run means this run set the new record.
    if level.map_tier > 0 && level.map_tier == best_score {
        rl.DrawTextEx(hud.font, "New best!", [2]f32 {panel_x + 24, panel_y + 84}, 13, 1, EXTRACT_COLOR)
    }

    rl.DrawTextEx(hud.font, "Press ENTER to restart", [2]f32 {panel_x + 24, panel_y + panel_h - 36}, 13, 1, HUD_LABEL_COLOR)
}