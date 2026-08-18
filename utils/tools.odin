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

// Sutherland-Hodgman clip against a single half-plane: points P where
// dot(P - plane_point, inside_normal) >= 0 are kept. `clipped` reports
// whether anything was actually cut away (some vertex was outside) — callers
// building a Voronoi cell from repeated half-plane clips use that to detect
// which other seed points actually border this one.
clip_polygon_halfplane :: proc(poly: [][2]f32, plane_point, inside_normal: [2]f32) -> (result: [dynamic][2]f32, clipped: bool) {
    n := len(poly)
    if n == 0 {
        return
    }
    result = make([dynamic][2]f32, 0, n + 1)

    prev := poly[n - 1]
    prev_d := (prev.x - plane_point.x) * inside_normal.x + (prev.y - plane_point.y) * inside_normal.y

    for i in 0..<n {
        curr := poly[i]
        curr_d := (curr.x - plane_point.x) * inside_normal.x + (curr.y - plane_point.y) * inside_normal.y

        if curr_d >= 0 {
            if prev_d < 0 {
                t := prev_d / (prev_d - curr_d)
                append(&result, prev + (curr - prev) * t)
            }
            append(&result, curr)
        } else {
            clipped = true
            if prev_d >= 0 {
                t := prev_d / (prev_d - curr_d)
                append(&result, prev + (curr - prev) * t)
            }
        }

        prev = curr
        prev_d = curr_d
    }

    return
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

vec2_point_segment_dist :: proc(p, a, b: [2]f32) -> f32 {
    ab := b - a
    len_sq := ab.x * ab.x + ab.y * ab.y
    if len_sq == 0 {
        return vec2_dist(p, a)
    }

    t := ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / len_sq
    t = clamp(t, 0, 1)
    closest := a + ab * t
    return vec2_dist(p, closest)
}