package models

import "core:math"

Chunk :: struct {
    meteors : [dynamic]int,
    bots    : [dynamic]int,
    visited : bool,
}

Active_Chunks :: struct {
    indices: [9]int,
    count:   int,
}

is_chunk_active :: proc(level: ^Level, chunk_idx: int) -> bool {
    neighbors := get_neighboring_chunks(level.last_player_chunk)
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

get_neighboring_chunks :: proc(center_chunk_idx: int) -> Active_Chunks {
    result: Active_Chunks

    center_gx := center_chunk_idx % GRID_WIDTH
    center_gy := center_chunk_idx / GRID_WIDTH

    for dy in -1..=1 {
        for dx in -1..=1 {
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

    neighbors := get_neighboring_chunks(center_chunk_idx)

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