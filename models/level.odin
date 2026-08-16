package models

import "../enums"
import "../utils"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

METEOR_IN_LEVEL   :: 300
CAMERA_LERP_SPEED :: 5.0
CHUNK_SIZE        :: 1000.0
GRID_WIDTH        :: 10
GRID_HEIGHT       :: 10

// --- STRUCTURES DU MONDE ---

Chunk :: struct {
    meteors : [dynamic]int,
    bots    : [dynamic]int,
}

Active_Chunks :: struct {
    indices: [9]int,
    count:   int,
}

Level :: struct {
    camera            : rl.Camera2D,
    ship              : Ship,
    last_player_chunk : int,
    meteors           : Pool(Meteor),
    bots              : Pool(Bot),
    chunks            : [100]Chunk,
    active_meteors    : [dynamic]int,
    active_bots       : [dynamic]int,
}

// --- UTILITAIRES DE CHUNKS ---

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

// --- CYCLE DE VIE DU LEVEL ---

level_create :: proc(level: ^Level, width, height: i32) {
    level.camera = rl.Camera2D {
        target   = level.ship.position,
        offset   = { f32(rl.GetScreenWidth()) / 2, f32(rl.GetScreenHeight()) / 2 },
        rotation = 0,
        zoom     = 1,
    }

    materials_selector := make([dynamic]enums.Materials, 0, context.temp_allocator)
    materials_repartition_keys := [4]enums.Materials {
        enums.Materials.Iron, enums.Materials.Silver,
        enums.Materials.Gold, enums.Materials.Osmium,
    }
    materials_repartition_values := [4]int {
        enums.material_presence(enums.Materials.Iron),
        enums.material_presence(enums.Materials.Silver),
        enums.material_presence(enums.Materials.Gold),
        enums.material_presence(enums.Materials.Osmium),
    }
    for i in 0..<4 {
        for _ in 0..<materials_repartition_values[i] {
            append(&materials_selector, materials_repartition_keys[i])
        }
    }

    for _ in 0..<METEOR_IN_LEVEL {
        x := rand.float32() * f32(width)
        y := rand.float32() * f32(height)
        mat := materials_selector[rand.int_max(len(materials_selector))]
        
        meteor_data := meteor_create(x, y, mat)
        meteor_id := pool_add(&level.meteors, meteor_data)
        
        chunk_idx := get_chunk_index(x, y)
        append(&level.chunks[chunk_idx].meteors, meteor_id)
    }

    bot_pos := [2]f32{50, 250}
    bot_data := Bot {
        dead      = false,
        type      = enums.BotType.Kamikaze,
        position  = bot_pos,
        direction = 0,
    }
    bot_id := pool_add(&level.bots, bot_data)
    bot_chunk_idx := get_chunk_index(bot_pos.x, bot_pos.y)
    append(&level.chunks[bot_chunk_idx].bots, bot_id)

    initial_chunk := get_chunk_index(level.ship.position.x, level.ship.position.y)
    level.last_player_chunk = initial_chunk
    populate_active_zone(level, initial_chunk)
}

level_update :: proc(level: ^Level, dt: f32) {
    ship_update(&level.ship, level.meteors.items[:], level.camera, dt)

    player_chunk := get_chunk_index(level.ship.position.x, level.ship.position.y)
    if player_chunk != level.last_player_chunk {
        level.last_player_chunk = player_chunk
        populate_active_zone(level, player_chunk)
    }

    for id in level.active_meteors {
        meteor := &level.meteors.items[id]
        meteor_update(meteor, dt)
    }

    #reverse for id, i in level.active_bots {
        bot := &level.bots.items[id]
        old_chunk := get_chunk_index(bot.position.x, bot.position.y)

        bot_update(bot, &level.ship, dt)

        if bot.dead {
            remove_id_from_slice(&level.chunks[old_chunk].bots, id)
            pool_remove(&level.bots, id)
            unordered_remove(&level.active_bots, i)
            continue
        }

        new_chunk := get_chunk_index(bot.position.x, bot.position.y)
        if new_chunk != old_chunk {
            remove_id_from_slice(&level.chunks[old_chunk].bots, id)
            append(&level.chunks[new_chunk].bots, id)

            if !is_chunk_active(level, new_chunk) {
                unordered_remove(&level.active_bots, i)
            }
        }
    }

    target := level.ship.position
    t := 1 - math.exp(-CAMERA_LERP_SPEED * dt)
    level.camera.target = utils.vec2_lerp(level.camera.target, target, t)
}

level_render :: proc(level: ^Level) {
    for id in level.active_meteors {
        meteor := level.meteors.items[id]
        meteor_render(meteor)
    }
    for id in level.active_bots {
        bot := level.bots.items[id]
        bot_render(bot, level.ship)
    }
}