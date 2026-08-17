package models

import rl "vendor:raylib"
import "core:math"
import "core:math/rand"
import "../utils"
import "../enums"

VERTEX_PER_METEOR :: 25
MIN_METEOR_VERTICES :: 4
METEOR_MINIMUM_SIZE :: 40
METEOR_MAXIMUM_SIZE :: 80
METEOR_VERTICES_VARIATION :: 15
METEOR_CUT_RATE :: 60.0
METEOR_CUT_FALLOFF :: 0.2
METEOR_YIELD_RATE :: 0.02
MIN_EDGE_LENGTH_FOR_INSERT :: 15

Meteor :: struct {
    vertices: [dynamic][2]f32,
    position: [2]f32,
    spin: f32,
    material: enums.Materials
}

meteor_create :: proc(x, y: f32, material: enums.Materials) -> Meteor {
    vertices := make([dynamic][2]f32, 0, VERTEX_PER_METEOR)
    size: i32 = rand.int31_max(METEOR_MAXIMUM_SIZE - METEOR_MINIMUM_SIZE) + METEOR_MINIMUM_SIZE
    angle: f32 = 0
    for _ in 0..<VERTEX_PER_METEOR {
        dist: f32 = f32(size + rand.int31_max(METEOR_VERTICES_VARIATION) - METEOR_VERTICES_VARIATION / 2)
        append(&vertices, [2]f32 {
            math.cos(angle) * dist + x,
            math.sin(angle) * dist + y,
        })
        angle = angle + math.TAU / VERTEX_PER_METEOR
    }
    return Meteor {
        vertices = vertices,
        position = [2]f32 {x, y},
        spin = (rand.float32() * 0.6 + 0.1) * (i32(math.round(x + y)) % 2 == 0 ? -1 : 1),
        material = material
    }
}

meteor_update :: proc(meteor: ^Meteor, dt: f32) {
    centroid := meteor_compute_centroid(meteor^)
    angle := meteor.spin * dt
    for &v in meteor.vertices {
        v = utils.rotate_vec2_around(v, centroid, angle)
    }
    meteor.position = centroid
}

meteor_render :: proc(meteor: Meteor) {
    color: rl.Color = enums.material_color(meteor.material)
    n := len(meteor.vertices)
    for i in 0..<n {
        rl.DrawLineEx(
            meteor.vertices[i],
            meteor.vertices[(i + 1) % n],
            2,
            color
        )
    }
}

meteor_compute_centroid :: proc(meteor: Meteor) -> [2]f32 {
    sum: [2]f32
    for v in meteor.vertices {
        sum += v
    }
    return sum / f32(len(meteor.vertices))
}

// Pushes a single vertex along push_dir at the given rate and returns how far
// it actually moved (used by the caller to compute mining yield). The only
// clamp is local: the vertex can't cross the chord formed by its own two
// immediate neighbors this frame. Without that, a big enough single-frame
// push could fold the polygon back on itself right at this vertex — a local
// "bowtie" that meteor_try_split's non-adjacent-edge scan would never catch
// (it only looks for FAR edges crossing), leaving a permanent rendering
// glitch instead of a clean split. There's deliberately no floor tied to the
// meteor's centroid: mining the same spot should keep making progress, frame
// after frame, until the deepening notch crosses a far edge and splits the
// rock — that's the intended terminal state, not a hard stop partway there.
meteor_deform_vertex :: proc(meteor: ^Meteor, index: int, push_dir: [2]f32, rate: f32, dt: f32) -> f32 {
    n := len(meteor.vertices)
    v := meteor.vertices[index]
    left := meteor.vertices[(index - 1 + n) % n]
    right := meteor.vertices[(index + 1) % n]
    moved := v + push_dir * rate * dt

    if clamp_point, crosses := utils.segment_intersection(v, moved, left, right); crosses {
        moved = clamp_point
    }

    meteor.vertices[index] = moved
    return utils.vec2_dist(v, moved)
}

// Handles a laser hit on edge (i, i+1) at world-space point `inter`. If that
// edge is still long enough to be worth subdividing (>= MIN_EDGE_LENGTH_FOR_INSERT),
// a new vertex is inserted exactly at `inter` so the cut lands pixel-precise
// instead of being approximated by whichever pre-existing vertices happen to
// be nearby, and it gets the full push while its two neighbors get a lighter
// falloff push for an organic-looking gouge. Below that length, further
// subdividing the same spot would just keep growing the vertex count for no
// visible benefit, so the two existing endpoints are pushed directly instead
// — this is what keeps vertex count (and therefore the O(n^2) self-intersection
// scan) bounded under sustained mining on one spot.
meteor_deform_edge :: proc(meteor: ^Meteor, i: int, inter: [2]f32, push_dir: [2]f32, dt: f32) -> f32 {
    n := len(meteor.vertices)
    right := (i + 1) % n
    edge_length := utils.vec2_dist(meteor.vertices[i], meteor.vertices[right])

    if edge_length < MIN_EDGE_LENGTH_FOR_INSERT {
        yield: f32 = 0
        yield += meteor_deform_vertex(meteor, i, push_dir, METEOR_CUT_RATE, dt)
        yield += meteor_deform_vertex(meteor, right, push_dir, METEOR_CUT_RATE, dt)
        return yield
    }

    inject_at(&meteor.vertices, i + 1, inter)
    new_n := n + 1
    new_vertex := i + 1
    shifted_right := (i + 2) % new_n

    yield: f32 = 0
    yield += meteor_deform_vertex(meteor, new_vertex, push_dir, METEOR_CUT_RATE, dt)
    yield += meteor_deform_vertex(meteor, i, push_dir, METEOR_CUT_RATE * METEOR_CUT_FALLOFF, dt)
    yield += meteor_deform_vertex(meteor, shifted_right, push_dir, METEOR_CUT_RATE * METEOR_CUT_FALLOFF, dt)
    return yield
}

// Scans the meteor's own boundary for a self-intersection (two non-adjacent
// edges crossing, e.g. after a deformation pinches the rock thin enough to
// fold over itself). If found, truncates `meteor` in place to one side of the
// cut. A valid other side is returned as a new fragment (has_fragment == true).
// A degenerate sliver (fewer than MIN_METEOR_VERTICES points) on either side
// is dropped instead of spawned; if both sides are degenerate the meteor is
// fully consumed and `destroyed` is set so the caller can remove it.
meteor_try_split :: proc(meteor: ^Meteor) -> (fragment: Meteor, has_fragment: bool, destroyed: bool) {
    n := len(meteor.vertices)
    if n < 4 {
        return {}, false, false
    }

    for i in 0..<n {
        a1 := meteor.vertices[i]
        a2 := meteor.vertices[(i + 1) % n]
        for j in i + 2..<n {
            if i == 0 && j == n - 1 {
                continue // edges (n-1,0) and (0,1) share vertex 0
            }
            b1 := meteor.vertices[j]
            b2 := meteor.vertices[(j + 1) % n]
            inter, hit := utils.segment_intersection(a1, a2, b1, b2)
            if !hit {
                continue
            }

            chain_a := make([dynamic][2]f32, 0, j - i + 2)
            append(&chain_a, inter)
            for k in i + 1..=j {
                append(&chain_a, meteor.vertices[k])
            }

            chain_b := make([dynamic][2]f32, 0, n - (j - i) + 2)
            append(&chain_b, inter)
            for k in j + 1..<n {
                append(&chain_b, meteor.vertices[k])
            }
            for k in 0..=i {
                append(&chain_b, meteor.vertices[k])
            }

            a_valid := len(chain_a) >= MIN_METEOR_VERTICES
            b_valid := len(chain_b) >= MIN_METEOR_VERTICES

            if !a_valid && !b_valid {
                delete(chain_a)
                delete(chain_b)
                return {}, false, true
            }
            if !a_valid {
                delete(chain_a)
                delete(meteor.vertices)
                meteor.vertices = chain_b
                meteor.position = meteor_compute_centroid(meteor^)
                return {}, false, false
            }
            if !b_valid {
                delete(chain_b)
                delete(meteor.vertices)
                meteor.vertices = chain_a
                meteor.position = meteor_compute_centroid(meteor^)
                return {}, false, false
            }

            delete(meteor.vertices)
            meteor.vertices = chain_a
            meteor.position = meteor_compute_centroid(meteor^)

            fragment = Meteor {
                vertices = chain_b,
                material = meteor.material,
                spin = meteor.spin,
            }
            fragment.position = meteor_compute_centroid(fragment)
            return fragment, true, false
        }
    }
    return {}, false, false
}

// The single entry point any component should use to damage a meteor with a
// swept segment — the laser uses ship.position -> ship.laser_target, and a
// future bot collision could use the bot's previous -> current position — so
// the mining/deformation/splitting rules only ever live here instead of being
// duplicated per attacker. Finds where (from -> to) crosses the boundary
// closest to `from`, carves that entry point in (meteor_deform_edge), and
// checks whether the deformation split the meteor or destroyed it outright
// (meteor_try_split). Returns hit == false, with every other value zeroed,
// if the segment never crosses the boundary at all.
meteor_hit :: proc(meteor: ^Meteor, from, to: [2]f32, dt: f32) -> (impact: [2]f32, yield: f32, fragment: Meteor, has_fragment: bool, destroyed: bool, hit: bool) {
    n := len(meteor.vertices)
    closest_i := 0
    closest_dist: f32 = math.F32_MAX

    // The boundary can be concave (post-deformation), so the segment may
    // cross more than one edge — e.g. entering through a near wall and again
    // through a far one. Only the nearest crossing to `from` is the real
    // entry point; deforming any other edge would push that wall's vertices
    // further along the segment's direction, which for a far/interior wall
    // means pushing them AWAY from `from` — i.e. outward, growing the rock
    // instead of carving it.
    for i in 0..<n {
        r1 := meteor.vertices[i]
        r2 := meteor.vertices[(i + 1) % n]
        inter, ok := utils.segment_intersection(from, to, r1, r2)
        if !ok {
            continue
        }
        dist := utils.vec2_dist(from, inter)
        if dist < closest_dist {
            hit = true
            closest_dist = dist
            impact = inter
            closest_i = i
        }
    }

    if !hit {
        return
    }

    push_dir := utils.vec2_normalize(to - from)
    yield = meteor_deform_edge(meteor, closest_i, impact, push_dir, dt) * METEOR_YIELD_RATE
    fragment, has_fragment, destroyed = meteor_try_split(meteor)
    return
}
