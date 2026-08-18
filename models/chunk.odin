package models

import "core:math"
import rl "vendor:raylib"
import "../utils"

Chunk :: struct {
    meteors : [dynamic]int,
    bots    : [dynamic]int,
    visited : bool,
}

// ACTIVE_RADIUS_MAX bounds how far the neighborhood can grow (5x5 chunks at
// radius 2) — comfortably covers even a 4K/ultrawide viewport at the current
// CHUNK_SIZE (see level.compute_active_radius), while keeping Active_Chunks a
// small fixed-size array instead of a dynamic one.
ACTIVE_RADIUS_MAX :: 2
Active_Chunks :: struct {
    indices: [(ACTIVE_RADIUS_MAX * 2 + 1) * (ACTIVE_RADIUS_MAX * 2 + 1)]int,
    count:   int,
}

// How many chunks out from the player's chunk are simulated/rendered.
// Fixed at 1 (a 3x3 neighborhood) used to hard-crop the world to whatever
// the original 1000-unit CHUNK_SIZE covered — on a big/high-res monitor
// where the viewport is wider than that, meteors near the screen edge would
// fall outside the active zone and simply not be there. Computed once at
// level_create/level_reset from the actual screen size instead, so the
// active zone always comfortably covers the viewport regardless of monitor.
compute_active_radius :: proc() -> int {
    half_diagonal := utils.norm_vec2([2]f32 {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}) / 2
    // +1 chunk of slack so meteors just outside the viewport are already
    // simulated a moment before they'd scroll into view.
    needed := int(math.ceil(half_diagonal / CHUNK_SIZE)) + 1
    return clamp(needed, 1, ACTIVE_RADIUS_MAX)
}

is_chunk_active :: proc(level: ^Level, chunk_idx: int) -> bool {
    neighbors := get_neighboring_chunks(level.last_player_chunk, level.active_radius)
    for i in 0..<neighbors.count {
        if neighbors.indices[i] == chunk_idx do return true
    }
    return false
}

get_chunk_index :: proc(x, y: f32) -> int {
    col := int(math.floor(x / CHUNK_SIZE))
    row := int(math.floor(y / CHUNK_SIZE))

    col = clamp(col, 0, GRID_WIDTH - 1)
    row = clamp(row, 0, GRID_HEIGHT - 1)

    return row * GRID_WIDTH + col
}

get_neighboring_chunks :: proc(center_chunk_idx: int, radius: int) -> Active_Chunks {
    result: Active_Chunks

    center_gx := center_chunk_idx % GRID_WIDTH
    center_gy := center_chunk_idx / GRID_WIDTH

    for dy in -radius..=radius {
        for dx in -radius..=radius {
            gx := center_gx + dx
            gy := center_gy + dy

            if gx >= 0 && gx < GRID_WIDTH && gy >= 0 && gy < GRID_HEIGHT {
                idx_1d := gy * GRID_WIDTH + gx
                result.indices[result.count] = idx_1d
                result.count += 1
            }
        }
    }

    return result
}

populate_active_zone :: proc(level: ^Level, center_chunk_idx: int) {
    clear(&level.active_meteors)
    clear(&level.active_bots)

    neighbors := get_neighboring_chunks(center_chunk_idx, level.active_radius)

    for i in 0..<neighbors.count {
        chunk_idx := neighbors.indices[i]
        chunk := &level.chunks[chunk_idx]

        append(&level.active_meteors, ..chunk.meteors[:])
        append(&level.active_bots,    ..chunk.bots[:])
    }
}

remove_id_from_slice :: proc(arr: ^[dynamic]int, id: int) -> bool {
    for val, i in arr {
        if val == id {
            unordered_remove(arr, i)
            return true
        }
    }
    return false
}