#+feature dynamic-literals

package models

import "core:fmt"
import rl "vendor:raylib"
import "../enums"
import "core:math"
import "../utils"
import "core:math/rand"

Game :: struct {
    state: enums.GameState,
    level: Level,
    width, height: i32,
    background: Background,
    hud: Hud,
}

game_init :: proc(game: ^Game) {
    rl.SetConfigFlags(rl.ConfigFlags { .MSAA_4X_HINT })
    rl.InitWindow(rl.GetScreenWidth(), rl.GetScreenHeight(), "Ember")
    game.state = enums.GameState.Run
    game.width = 10000
    game.height = 10000
    game.level.ship = Ship {
        position = [2]f32{LEVEL_WIDTH * (rand.float32() * 0.8 + 0.2), LEVEL_HEIGHT * (rand.float32() * 0.8 + 0.2)},
        max_capacity = 100,
        max_integrity = 100,
        integrity = 100,
        max_speed = SHIP_MAX_SPEED,
        laser_damage_mult = 1,
        fuel = FUEL_MAX_BASE,
        max_fuel = FUEL_MAX_BASE,
        laser_energy = LASER_ENERGY_MAX_BASE,
        max_laser_energy = LASER_ENERGY_MAX_BASE,
        stocks = map[enums.Materials]f32 {
            enums.Materials.Iron = 0,
            enums.Materials.Silver = 0,
            enums.Materials.Gold = 0,
            enums.Materials.Osmium = 0,
        }
    }
    level_create(&game.level)
    background_init(&game.background, game.width, game.height)
    hud_init(&game.hud, rl.GetScreenWidth(), rl.GetScreenHeight())
    rl.SetTargetFPS(180)
}

game_run :: proc(game: ^Game) {
    rl.SetMouseCursor(.CROSSHAIR)
    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        game_update(game, rl.GetFrameTime())
        game_render(game)
        rl.EndDrawing()
    }
    rl.CloseWindow()
}

game_update :: proc(game: ^Game, dt: f32) {
    level_update(&game.level, dt)
}

game_render :: proc(game: ^Game) {
    if game.state == enums.GameState.Menu {
        game_render_menu(game^)
    } else if game.state == enums.GameState.Run {
        rl.BeginMode2D(game.level.camera)
        game_render_run(game)
        rl.EndMode2D()
        hud_render(game.hud, &game.level)

    }
}

game_render_menu :: proc(game: Game) {

}

game_render_run :: proc(game: ^Game) {
    background_render(game.background, game.level.ship)
    level_render(&game.level)
}