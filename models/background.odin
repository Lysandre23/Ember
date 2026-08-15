package models

import rl "vendor:raylib"
import "core:math/rand"
import "../utils"

NUMBER_OF_STARS :: 1000

Background :: struct {
    stars: [NUMBER_OF_STARS]BackgroundStar
}

BackgroundStar :: struct {
    position: [2]f32,
    size: f32
}

background_init :: proc(background: ^Background, width, height: i32) {
    for i in 0..<NUMBER_OF_STARS {
        background.stars[i] = BackgroundStar {
            position = [2]f32 {
                f32(rand.int31_max(width)),
                f32(rand.int31_max(height))
            },
            size = f32(rand.int31_max(2)) + 1
        }
    }
}

background_render :: proc(background: Background, player: Player) {
    max_dist := utils.norm_vec2([2]f32 {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())})
    for star in background.stars {
        if utils.vec2_dist(star.position, player.ship.position) < max_dist {
            rl.DrawCircleV(star.position, star.size, rl.Color {255, 255, 255, 100})
        }
    }
}