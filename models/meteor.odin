package models

import rl "vendor:raylib"
import "core:math"
import "core:math/rand"
import "../utils"
import "../enums"

VERTEX_PER_METEOR :: 25
METEOR_MINIMUM_SIZE :: 40
METEOR_MAXIMUM_SIZE :: 80
METEOR_VERTICES_VARIATION :: 15
MIN_RADIUS :: 15

Meteor :: struct {
    position: [2]f32,
    vertices: [VERTEX_PER_METEOR]f32,
    rotation: f32,
    direction: f32,
    material: enums.Materials
}

meteor_create :: proc(x, y: f32, material: enums.Materials) -> Meteor {
    vertices: [VERTEX_PER_METEOR]f32
    size: i32 = rand.int31_max(METEOR_MAXIMUM_SIZE - METEOR_MINIMUM_SIZE) + METEOR_MINIMUM_SIZE
    angle: f32 = 0
    for i in 0..<VERTEX_PER_METEOR {
        dist: f32 = f32(size + rand.int31_max(METEOR_VERTICES_VARIATION) - METEOR_VERTICES_VARIATION / 2)
        vx: f32 = math.cos(angle) * dist + x
        vy: f32 = math.sin(angle) * dist + y
        vertices[i] = dist
        angle = angle + math.TAU / VERTEX_PER_METEOR
    }
    return Meteor { 
        position = [2]f32 {x, y}, 
        vertices = vertices, 
        rotation = (rand.float32() * 0.6 + 0.1) * (rand.float32() < 0.5 ? -1 : 1),
        material = material
    }
}

meteor_update :: proc(meteor: ^Meteor, dt: f32) {
    meteor.direction += 0.1 * dt
}

meteor_render :: proc(meteor: Meteor) {
    color: rl.Color = enums.material_color(meteor.material)
    for i in 0..<VERTEX_PER_METEOR {
        v1 := meteor.vertices[i]
        v2 := meteor.vertices[(i + 1) % VERTEX_PER_METEOR]
        rl.DrawLineEx(
            meteor_get_vertice_position(meteor, i),
            meteor_get_vertice_position(meteor, (i + 1) % VERTEX_PER_METEOR),
            2,
            color
        )
        
    }
}

meteor_get_vertice_position :: proc(meteor: Meteor, index: int) -> [2]f32 {
    return [2]f32 {
        meteor.position.x + math.cos(meteor.direction + math.TAU / VERTEX_PER_METEOR * f32(index)) * meteor.vertices[index],
        meteor.position.y + math.sin(meteor.direction + math.TAU / VERTEX_PER_METEOR * f32(index)) * meteor.vertices[index]
    }
}