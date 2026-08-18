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

CELL_COUNT_MIN :: 16
CELL_COUNT_MAX :: 32
CELL_MAX_HP :: 7.5
CELL_DAMAGE_RATE :: 40.0
CELL_YIELD_RATE :: 0.05
CELL_SEED_PLACEMENT_RETRIES :: 20
CELL_MIN_SEED_SPACING_FACTOR :: 0.6
BOUNDARY_EDGE_EPSILON :: 0.5

METEOR_VELOCITY_DAMPING :: 0.15       // fraction of velocity retained after 1s
METEOR_SPLIT_SEPARATION_SPEED :: 45.0
METEOR_SPLIT_SPIN_VARIATION :: 0.35

// A meteor is pre-partitioned into small convex Voronoi cells at creation
// time instead of being one deformable polygon. Mining damages whichever
// cell the beam is touching; a cell just disappears once its hp is spent.
// That trades the old organic-but-unpredictable vertex deformation for
// something far more legible: every chunk takes a fixed, predictable amount
// of firing to pop, and "how much is left" is just "how many cells are left."
MeteorCell :: struct {
    vertices: [dynamic][2]f32, // convex polygon, absolute world-space points
    neighbors: [dynamic]int,   // indices into the OWNING meteor's cells array
    boundary: [dynamic]bool,   // boundary[i], parallel to vertices: draw edge i?
    hp, max_hp: f32,
    dead: bool,
}

Meteor :: struct {
    cells: [dynamic]MeteorCell,
    position: [2]f32, // centroid of alive cells: chunk placement & broad-phase
    spin: f32,
    velocity: [2]f32, // only ever nonzero right after a split — see meteor_apply_split_kick
    material: enums.Materials,

    // Conservative avoidance/collision radius (models/bot.odin's steering,
    // level.odin's level_meteor_impact broad-phase). Set once at creation
    // and recomputed only when the meteor actually splits (meteor_check_split)
    // — chipping individual cells without a split doesn't shrink it, since
    // recomputing on every single hit would cost real per-frame work for a
    // value that's only ever used as a rough safety margin.
    avoid_radius: f32,
}

meteor_create :: proc(x, y: f32, material: enums.Materials) -> Meteor {
    size: f32 = f32(rand.int31_max(METEOR_MAXIMUM_SIZE - METEOR_MINIMUM_SIZE) + METEOR_MINIMUM_SIZE)

    silhouette := make([dynamic][2]f32, 0, VERTEX_PER_METEOR, context.temp_allocator)
    angle: f32 = 0
    for _ in 0..<VERTEX_PER_METEOR {
        dist: f32 = size + f32(rand.int31_max(METEOR_VERTICES_VARIATION)) - METEOR_VERTICES_VARIATION / 2
        append(&silhouette, [2]f32 {
            math.cos(angle) * dist + x,
            math.sin(angle) * dist + y,
        })
        angle = angle + math.TAU / VERTEX_PER_METEOR
    }

    size_range: f32 = f32(METEOR_MAXIMUM_SIZE - METEOR_MINIMUM_SIZE)
    size_t := (size - f32(METEOR_MINIMUM_SIZE)) / size_range
    cell_count := CELL_COUNT_MIN + int(size_t * f32(CELL_COUNT_MAX - CELL_COUNT_MIN))
    min_spacing := size / math.sqrt(f32(cell_count)) * CELL_MIN_SEED_SPACING_FACTOR

    // Rejection sampling with a retry cap — same shape as level_spawn_poi's
    // placement loop (models/level.odin). Seeds are placed within 75% of the
    // silhouette's base radius, comfortably inside even its tightest jitter,
    // so no point-in-polygon test is needed. Failing to place a seed within
    // the retry cap just means fewer cells than requested, not a bug.
    seeds := make([dynamic][2]f32, 0, cell_count, context.temp_allocator)
    for _ in 0..<cell_count {
        for _ in 0..<CELL_SEED_PLACEMENT_RETRIES {
            theta := rand.float32() * math.TAU
            radius := rand.float32() * size * 0.75
            candidate := [2]f32 { x + math.cos(theta) * radius, y + math.sin(theta) * radius }

            ok := true
            for seed in seeds {
                if utils.vec2_dist(candidate, seed) < min_spacing {
                    ok = false
                    break
                }
            }
            if ok {
                append(&seeds, candidate)
                break
            }
        }
    }

    // Each seed's cell is the intersection of half-planes against every
    // other seed's perpendicular bisector — the standard Voronoi-cell
    // construction, clipped to the silhouette. Cells built this way are
    // always convex. If a clip against seed j actually removes area from
    // seed i's polygon, i and j are recorded as neighbors (used later for
    // the flood-fill that detects a mining-induced split).
    cells := make([dynamic]MeteorCell, 0, len(seeds))
    for i in 0..<len(seeds) {
        poly := make([dynamic][2]f32, 0, len(silhouette))
        append(&poly, ..silhouette[:])

        neighbors := make([dynamic]int)
        for j in 0..<len(seeds) {
            if i == j || len(poly) < 3 {
                continue
            }
            plane_point := (seeds[i] + seeds[j]) * 0.5
            inside_normal := utils.vec2_normalize(seeds[i] - seeds[j])
            clipped_poly, clipped := utils.clip_polygon_halfplane(poly[:], plane_point, inside_normal)
            delete(poly)
            poly = clipped_poly
            if clipped {
                append(&neighbors, j)
            }
        }

        dead := len(poly) < 3
        append(&cells, MeteorCell {
            vertices = poly,
            neighbors = neighbors,
            hp = dead ? 0 : CELL_MAX_HP,
            max_hp = CELL_MAX_HP,
            dead = dead,
        })
    }

    // Adjacency as recorded above is directional (i found j, doesn't imply j
    // found i); make it symmetric so the flood-fill can walk either way.
    for i in 0..<len(cells) {
        for j in cells[i].neighbors {
            if j < 0 || j >= len(cells) {
                continue
            }
            already := false
            for k in cells[j].neighbors {
                if k == i {
                    already = true
                    break
                }
            }
            if !already {
                append(&cells[j].neighbors, i)
            }
        }
    }

    meteor := Meteor {
        cells = cells,
        spin = (rand.float32() * 0.6 + 0.1) * (i32(math.round(x + y)) % 2 == 0 ? -1 : 1),
        material = material,
    }
    meteor_recompute_boundaries(&meteor)
    meteor.position = meteor_compute_centroid(meteor)
    meteor.avoid_radius = meteor_compute_radius(meteor)
    return meteor
}

// Farthest any alive cell vertex sits from the meteor's own centroid — a
// cheap circle bound used wherever an exact per-cell-edge test would be
// overkill (bot steering, bullet blocking).
meteor_compute_radius :: proc(meteor: Meteor) -> f32 {
    max_dist: f32 = 0
    for cell in meteor.cells {
        if cell.dead {
            continue
        }
        for v in cell.vertices {
            d := utils.vec2_dist(v, meteor.position)
            if d > max_dist {
                max_dist = d
            }
        }
    }
    return max_dist
}

// An edge is drawn only if the cell across it isn't a still-alive neighbor —
// i.e. it's either a true silhouette edge or one now exposed by a dead
// neighbor — so internal Voronoi seams between two intact cells never
// render, and a mined-out cell reads as a visible crater instead of a gap
// hidden behind still-drawn seam lines. Matching is geometric (do the two
// endpoints coincide, in reverse order, with some other alive neighbor's
// edge) rather than tracking per-edge provenance through the clip — cells
// only number in the dozens, and this only needs to run once at creation and
// once whenever a cell dies (meteor_kill_cell), never per frame or per hit.
meteor_recompute_boundaries :: proc(meteor: ^Meteor) {
    for &cell in meteor.cells {
        if cell.dead {
            continue
        }
        n := len(cell.vertices)
        if len(cell.boundary) != n {
            delete(cell.boundary)
            cell.boundary = make([dynamic]bool, n)
        }
        for i in 0..<n {
            a1 := cell.vertices[i]
            a2 := cell.vertices[(i + 1) % n]
            shared := false
            neighbor_scan: for neighbor_idx in cell.neighbors {
                if neighbor_idx < 0 || neighbor_idx >= len(meteor.cells) {
                    continue
                }
                neighbor := meteor.cells[neighbor_idx]
                if neighbor.dead {
                    continue
                }
                nn := len(neighbor.vertices)
                for j in 0..<nn {
                    b1 := neighbor.vertices[j]
                    b2 := neighbor.vertices[(j + 1) % nn]
                    if utils.vec2_dist(a1, b2) < BOUNDARY_EDGE_EPSILON && utils.vec2_dist(a2, b1) < BOUNDARY_EDGE_EPSILON {
                        shared = true
                        break neighbor_scan
                    }
                }
            }
            cell.boundary[i] = !shared
        }
    }
}

meteor_update :: proc(meteor: ^Meteor, dt: f32) {
    if meteor.velocity.x != 0 || meteor.velocity.y != 0 {
        offset := meteor.velocity * dt
        for &cell in meteor.cells {
            if cell.dead {
                continue
            }
            for &v in cell.vertices {
                v += offset
            }
        }
        meteor.velocity *= math.pow(f32(METEOR_VELOCITY_DAMPING), dt)
        if utils.norm_vec2(meteor.velocity) < 0.5 {
            meteor.velocity = {0, 0}
        }
    }

    centroid := meteor_compute_centroid(meteor^)
    angle := meteor.spin * dt
    for &cell in meteor.cells {
        if cell.dead {
            continue
        }
        for &v in cell.vertices {
            v = utils.rotate_vec2_around(v, centroid, angle)
        }
    }
    meteor.position = centroid
}

meteor_render :: proc(meteor: Meteor) {
    color: rl.Color = enums.material_color(meteor.material)
    for cell in meteor.cells {
        if cell.dead {
            continue
        }
        n := len(cell.vertices)
        for i in 0..<n {
            if !cell.boundary[i] {
                continue
            }
            rl.DrawLineEx(cell.vertices[i], cell.vertices[(i + 1) % n], 2, color)
        }
    }
}

meteor_compute_centroid :: proc(meteor: Meteor) -> [2]f32 {
    sum: [2]f32
    count := 0
    for cell in meteor.cells {
        if cell.dead {
            continue
        }
        for v in cell.vertices {
            sum += v
        }
        count += len(cell.vertices)
    }
    if count == 0 {
        return sum
    }
    return sum / f32(count)
}

meteor_destroy :: proc(meteor: ^Meteor) {
    for &cell in meteor.cells {
        delete(cell.vertices)
        delete(cell.neighbors)
        delete(cell.boundary)
    }
    delete(meteor.cells)
}

meteor_kill_cell :: proc(meteor: ^Meteor, index: int) {
    delete(meteor.cells[index].vertices)
    delete(meteor.cells[index].neighbors)
    delete(meteor.cells[index].boundary)
    meteor.cells[index].vertices = nil
    meteor.cells[index].neighbors = nil
    meteor.cells[index].boundary = nil
    meteor.cells[index].dead = true
    meteor_recompute_boundaries(meteor)
}

// The single entry point any component should use to damage a meteor with a
// swept segment — the laser uses ship.position -> ship.laser_target, and a
// future bot collision could use the bot's previous -> current position — so
// the mining/damage/splitting rules only ever live here instead of being
// duplicated per attacker. Finds the alive cell whose boundary the segment
// crosses closest to `from`, applies damage to it, and — only if that
// killed the cell — checks whether the meteor split or was fully consumed.
// Returns hit == false, with every other value zeroed, if the segment never
// crosses any alive cell's boundary.
meteor_hit :: proc(meteor: ^Meteor, from, to: [2]f32, damage_mult: f32, dt: f32) -> (impact: [2]f32, yield: f32, fragments: [dynamic]Meteor, destroyed: bool, hit: bool) {
    closest_cell := -1
    closest_dist: f32 = math.F32_MAX

    for cell, ci in meteor.cells {
        if cell.dead {
            continue
        }
        n := len(cell.vertices)
        for i in 0..<n {
            r1 := cell.vertices[i]
            r2 := cell.vertices[(i + 1) % n]
            inter, ok := utils.segment_intersection(from, to, r1, r2)
            if !ok {
                continue
            }
            dist := utils.vec2_dist(from, inter)
            if dist < closest_dist {
                hit = true
                closest_dist = dist
                impact = inter
                closest_cell = ci
            }
        }
    }

    if !hit {
        return
    }

    cell := &meteor.cells[closest_cell]
    damage := CELL_DAMAGE_RATE * damage_mult * dt
    if damage > cell.hp {
        damage = cell.hp
    }
    cell.hp -= damage
    yield = damage * CELL_YIELD_RATE

    if cell.hp <= 0 {
        meteor_kill_cell(meteor, closest_cell)
        fragments, destroyed = meteor_check_split(meteor)
    }

    return
}

// A one-off impact (a ram, a fast pass-through) expressed directly in hp
// rather than through meteor_hit's damage_mult/dt product — used by
// anything that hits a meteor for a single instant instead of a sustained
// beam (bot ramming and the strike drone in models/bot.odin/drone.odin, via
// level.odin's level_meteor_impact). dt=1 makes damage_mult*CELL_DAMAGE_RATE
// equal exactly `damage`.
meteor_hit_impact :: proc(meteor: ^Meteor, from, to: [2]f32, damage: f32) -> (impact: [2]f32, yield: f32, fragments: [dynamic]Meteor, destroyed: bool, hit: bool) {
    return meteor_hit(meteor, from, to, damage / CELL_DAMAGE_RATE, 1)
}

// Kicks a just-split piece outward from where the whole rock used to be
// centered, and nudges its spin away from the original — without this, a
// freshly split-off piece has the exact same position and spin as before
// the split and just reads as part of the same still-life rock.
meteor_apply_split_kick :: proc(piece: ^Meteor, origin: [2]f32) {
    direction := utils.vec2_normalize(piece.position - origin)
    speed := METEOR_SPLIT_SEPARATION_SPEED * (0.7 + rand.float32() * 0.6)
    piece.velocity = direction * speed
    piece.spin += (rand.float32() * 2 - 1) * METEOR_SPLIT_SPIN_VARIATION
}

// Runs only right after a cell has just died (the only moment connectivity
// can change). Flood-fills the alive cells via their neighbor lists; if
// that's still a single connected group, there's nothing to do — the common
// case (chipping a still-solid rock) never pays for a rebuild. If killing
// that cell split the survivors into two or more groups, the largest stays
// as `meteor` and every other group is spun off as an independent fragment.
meteor_check_split :: proc(meteor: ^Meteor) -> (fragments: [dynamic]Meteor, destroyed: bool) {
    n := len(meteor.cells)

    alive_count := 0
    for cell in meteor.cells {
        if !cell.dead {
            alive_count += 1
        }
    }
    if alive_count == 0 {
        destroyed = true
        return
    }

    visited := make([dynamic]bool, n)
    defer delete(visited)

    components := make([dynamic][dynamic]int, 0, 4)
    defer {
        for component in components {
            delete(component)
        }
        delete(components)
    }

    for start in 0..<n {
        if meteor.cells[start].dead || visited[start] {
            continue
        }
        component := make([dynamic]int, 0, alive_count)
        stack := make([dynamic]int, 0, alive_count)
        append(&stack, start)
        visited[start] = true
        for len(stack) > 0 {
            idx := pop(&stack)
            append(&component, idx)
            for neighbor in meteor.cells[idx].neighbors {
                if neighbor < 0 || neighbor >= n {
                    continue
                }
                if meteor.cells[neighbor].dead || visited[neighbor] {
                    continue
                }
                visited[neighbor] = true
                append(&stack, neighbor)
            }
        }
        delete(stack)
        append(&components, component)
    }

    if len(components) <= 1 {
        return
    }

    largest := 0
    for i in 1..<len(components) {
        if len(components[i]) > len(components[largest]) {
            largest = i
        }
    }

    // Every new cells array (the kept one and every fragment's) is built
    // from the ORIGINAL meteor.cells before any of it is torn down — cell
    // structs (their vertices/neighbors/boundary arrays included) are moved
    // by value into whichever new array claims them, so meteor.cells can
    // only be deleted once every component has already been pulled out of
    // it. boundary doesn't need recomputing here: flood-fill only separates
    // cells that weren't connected by a still-alive shared edge in the first
    // place, so every edge along a new split seam was already boundary=true
    // (it bordered whichever dead cell caused the split).
    // Everything used to be one rigid body sharing meteor.position/spin — a
    // split has to visibly break that or the two pieces just sit exactly
    // where the whole rock was, spinning in lockstep, reading as one entity.
    // meteor.position here is still last frame's centroid of the *whole*
    // pre-split group, which is exactly the "explosion origin" every piece
    // should be kicked away from.
    origin := meteor.position
    original_spin := meteor.spin

    kept_cells := meteor_rebuild_cells(meteor^, components[largest][:])

    fragment_cell_lists := make([dynamic][dynamic]MeteorCell, 0, len(components) - 1)
    defer delete(fragment_cell_lists)
    for i in 0..<len(components) {
        if i == largest {
            continue
        }
        append(&fragment_cell_lists, meteor_rebuild_cells(meteor^, components[i][:]))
    }

    delete(meteor.cells)
    meteor.cells = kept_cells
    meteor.position = meteor_compute_centroid(meteor^)
    meteor.avoid_radius = meteor_compute_radius(meteor^)
    meteor_apply_split_kick(meteor, origin)

    for cells in fragment_cell_lists {
        fragment := Meteor {
            cells = cells,
            spin = original_spin,
            material = meteor.material,
        }
        fragment.position = meteor_compute_centroid(fragment)
        fragment.avoid_radius = meteor_compute_radius(fragment)
        meteor_apply_split_kick(&fragment, origin)
        append(&fragments, fragment)
    }

    return
}

// Pulls the cells at component_indices (original indices into meteor.cells)
// out into a fresh, densely-indexed array, remapping each moved cell's
// neighbor list to the new indices and dropping any neighbor reference that
// isn't part of this component (it now belongs to a different meteor).
meteor_rebuild_cells :: proc(meteor: Meteor, component_indices: []int) -> [dynamic]MeteorCell {
    old_to_new := make([dynamic]int, len(meteor.cells))
    defer delete(old_to_new)
    for i in 0..<len(old_to_new) {
        old_to_new[i] = -1
    }
    for i in 0..<len(component_indices) {
        old_to_new[component_indices[i]] = i
    }

    result := make([dynamic]MeteorCell, 0, len(component_indices))
    for old_idx in component_indices {
        old_cell := meteor.cells[old_idx]
        new_neighbors := make([dynamic]int, 0, len(old_cell.neighbors))
        for neighbor in old_cell.neighbors {
            mapped := old_to_new[neighbor]
            if mapped >= 0 {
                append(&new_neighbors, mapped)
            }
        }
        append(&result, MeteorCell {
            vertices = old_cell.vertices,
            neighbors = new_neighbors,
            boundary = old_cell.boundary,
            hp = old_cell.hp,
            max_hp = old_cell.max_hp,
            dead = false,
        })
    }
    return result
}
