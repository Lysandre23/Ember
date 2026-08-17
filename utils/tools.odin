package utils

import "core:math"

rotate_vec2_around :: proc(v: [2]f32, center: [2]f32, angle: f32) -> [2]f32 {
    c := math.cos(angle)
    s := math.sin(angle)

    p := v - center

    rotated := [2]f32{
        p.x * c - p.y * s,
        p.x * s + p.y * c,
    }

    return rotated + center
}

norm_vec2 :: proc(v: [2]f32) -> f32 {
    return math.sqrt(math.pow(v.x, 2) + math.pow(v.y, 2))
}

vec2_dist :: proc(v1, v2: [2]f32) -> f32 {
    return math.sqrt(math.pow(v1.x - v2.x, 2) + math.pow(v1.y - v2.y, 2))
}

vec2_normalize :: proc(v: [2]f32) -> [2]f32 {
    length := norm_vec2(v)
    if length == 0 {
        return v
    }
    return v / length
}

vec2_lerp :: proc(a, b: [2]f32, t: f32) -> [2]f32 {
    return a + (b - a) * t
}

vec2_clamp_length :: proc(v: [2]f32, max_length: f32) -> [2]f32 {
    length_sq := v.x * v.x + v.y * v.y
    max_length_sq := max_length * max_length

    if length_sq > max_length_sq {
        length := math.sqrt(length_sq)
        return v * (max_length / length)
    }

    return v
}

segment_intersection :: proc(a1, a2, b1, b2: [2]f32) -> (point: [2]f32, ok: bool) {
    r := a2 - a1
    s := b2 - b1

    r_cross_s := r.x * s.y - r.y * s.x

    if math.abs(r_cross_s) < 1e-8 {
        return {}, false
    }

    qp := b1 - a1
    t := (qp.x * s.y - qp.y * s.x) / r_cross_s
    u := (qp.x * r.y - qp.y * r.x) / r_cross_s

    if t < 0 || t > 1 || u < 0 || u > 1 {
        return {}, false
    }

    point = a1 + r * t
    ok = true
    return
}