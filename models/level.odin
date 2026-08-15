package models

import "../enums"
import "core:math/rand"
import "../utils"
import rl "vendor:raylib"

METEOR_IN_LEVEL :: 300

Level :: struct {
    meteors: [dynamic]Meteor
}

// ----------------------------------------

level_create :: proc(level: ^Level, width, height: i32) {
    materials_selector := make([dynamic]enums.Materials, 0)
    materials_repartition_keys := [4]enums.Materials {
        enums.Materials.Iron, enums.Materials.Silver,
        enums.Materials.Gold, enums.Materials.Osmium
    }
    materials_repartition_values := [4]int {
        enums.material_presence(enums.Materials.Iron), enums.material_presence(enums.Materials.Silver),
        enums.material_presence(enums.Materials.Gold), enums.material_presence(enums.Materials.Osmium)
    }
    for i in 0..<4 {
        for j in 0..<materials_repartition_values[i] {
            append(&materials_selector, materials_repartition_keys[i])
        }
    }
    for i in 0..<METEOR_IN_LEVEL {
        x := rand.float32() * f32(width)
        y := rand.float32() * f32(height)
        append(
            &level.meteors, 
            meteor_create(
                x, y, 
                materials_selector[rand.int_max(len(materials_selector))])
            )
    }
}

level_update :: proc(level: ^Level, player: Player, dt: f32) {
    for &meteor in level.meteors {
        max_dist := utils.norm_vec2([2]f32 {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())})
        if utils.vec2_dist(meteor.position, player.ship.position) < max_dist {
            meteor_update(&meteor, dt)
        }
    }
}

level_render :: proc(level: Level, player: Player) {
    max_dist := utils.norm_vec2([2]f32 {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())})
    for meteor in level.meteors {
        if utils.vec2_dist(meteor.position, player.ship.position) < max_dist {
            meteor_render(meteor)
        }
    }
}