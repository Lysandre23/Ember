package models

import "core:fmt"
import rl "vendor:raylib"
import "../enums"
import "core:math"
import "../utils"

CAMERA_LERP_SPEED :: 5.0

Game :: struct {
    state: enums.GameState,
    level: Level,
    width, height: i32,
    camera: rl.Camera2D,
    player: Player,
    background: Background,
    hud: Hud,
}

game_init :: proc(game: ^Game) {
    rl.InitWindow(rl.GetScreenWidth(), rl.GetScreenHeight(), "Ember")
    screen_width := rl.GetScreenWidth()
    game.state = enums.GameState.Run
    game.width = 10000
    game.height = 10000
    level_create(&game.level, game.width, game.height)
    game.player = Player { ship = Ship { position = [2]f32{150, 150}, max_capacity = 100 } }
    background_init(&game.background, game.width, game.height)
    hud_init(&game.hud, rl.GetScreenWidth(), rl.GetScreenHeight())
    rl.SetTargetFPS(180)
}

game_run :: proc(game: ^Game) {
    game.camera = rl.Camera2D {
        target   = game.player.ship.position,
        offset   = { f32(rl.GetScreenWidth()) / 2, f32(rl.GetScreenHeight()) / 2 },
        rotation = 0,
        zoom     = 1,
    }
    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        game_update(game, rl.GetFrameTime())
        game_render(game^)
        rl.EndDrawing()
    }
    rl.CloseWindow()
}

game_update :: proc(game: ^Game, dt: f32) {
    level_update(&game.level, game.player, dt)
    player_update(&game.player, game.level.meteors, game.camera, dt)

    target := game.player.ship.position
    t := 1 - math.exp(-CAMERA_LERP_SPEED * dt)
    game.camera.target = utils.vec2_lerp(game.camera.target, target, t)
}

game_render :: proc(game: Game) {
    if game.state == enums.GameState.Menu {
        game_render_menu(game)
    } else if game.state == enums.GameState.Run {
        rl.BeginMode2D(game.camera)
        game_render_run(game)
        rl.EndMode2D()
        hud_render(game.hud, game.player)
        rl.DrawFPS(5, 5)
    }
}

game_render_menu :: proc(game: Game) {

}

game_render_run :: proc(game: Game) {
    background_render(game.background, game.player)
    level_render(game.level, game.player)
    player_render(game.player)
}