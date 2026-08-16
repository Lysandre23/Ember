package models

import "../enums"
import "../utils"
import "core:math"
import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"

METEOR_IN_LEVEL       :: 300
CAMERA_LERP_SPEED     :: 5.0
CHUNK_SIZE            :: 1000.0
GRID_WIDTH            :: 10
GRID_HEIGHT           :: 10
LEVEL_WIDTH           :: 10000
LEVEL_HEIGHT          :: 10000
HEAL_POI_NUMBER       :: 6
MIN_RANGE_BETWEEN_POI :: 3000



Level :: struct {
    camera            : rl.Camera2D,
    ship              : Ship,
    last_player_chunk : int,
    meteors           : Pool(Meteor),
    bots              : Pool(Bot),
    chunks            : [100]Chunk,
    active_meteors    : [dynamic]int,
    active_bots       : [dynamic]int,
    pois              : [dynamic]Poi,
    pause             : bool,
    display_map       : bool,
}

level_create :: proc(level: ^Level) {
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
        x := rand.float32() * f32(LEVEL_WIDTH)
        y := rand.float32() * f32(LEVEL_HEIGHT)
        mat := materials_selector[rand.int_max(len(materials_selector))]
        
        meteor_data := meteor_create(x, y, mat)
        meteor_id := pool_add(&level.meteors, meteor_data)
        
        chunk_idx := get_chunk_index(x, y)
        append(&level.chunks[chunk_idx].meteors, meteor_id)
    }

    level_spawn_bot(level, [2]f32 {50, 250})
    level_spawn_bot(level, [2]f32 {50, 300})

    initial_chunk := get_chunk_index(level.ship.position.x, level.ship.position.y)
    level.last_player_chunk = initial_chunk
    populate_active_zone(level, initial_chunk)

    level_spawn_poi(level, HEAL_POI_NUMBER, PoiType.Heal)
}

level_update :: proc(level: ^Level, dt: f32) {
    level.display_map = rl.IsKeyDown(.TAB)
    level.pause = level.display_map

    if level.pause {
        return
    }

    ship_update(&level.ship, level.meteors.items[:], level.camera, dt)

    for &poi in level.pois {
        poi_update(&poi, &level.ship, dt)
    }

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
    rl.DrawRectangleLinesEx(rl.Rectangle {
        0, 0, LEVEL_WIDTH, LEVEL_HEIGHT
    }, 2, rl.GRAY)
    for &poi, _ in level.pois {
        poi_render(&poi)
    }
    ship_render(level.ship)
    for id in level.active_meteors {
        meteor := level.meteors.items[id]
        meteor_render(meteor)
    }
    for id in level.active_bots {
        bot := level.bots.items[id]
        bot_render(bot, level.ship)
    }
}

level_spawn_bot :: proc(level: ^Level, position: [2]f32, type: enums.BotType = enums.BotType.Kamikaze) {
    bot_data := Bot {
        dead      = false,
        type      = type,
        position  = position,
        direction = 0,
    }
    bot_id := pool_add(&level.bots, bot_data)
    bot_chunk_idx := get_chunk_index(position.x, position.y)
    append(&level.chunks[bot_chunk_idx].bots, bot_id)
}

level_spawn_poi :: proc(level: ^Level, n: int, type: PoiType) {
    pois := make([dynamic]Poi)
    for i in 0..<n {
        can_place := false
        count := 0
        for !can_place && count < 15 {
            position := [2]f32 {rand.float32() * LEVEL_WIDTH, rand.float32() * LEVEL_HEIGHT}
            acceptable := true

            for poi in pois {
                if utils.vec2_dist(poi.position, position) < MIN_RANGE_BETWEEN_POI {
                    acceptable = false
                    break
                }
            }
            if acceptable {
                can_place = true
                append(&level.pois, Poi {
                    active = false,
                    position = position,
                    type = type
                })
            } else {
                count += 1
            }
            fmt.println(count)
        }
    }
}

level_render_map :: proc(level: Level) {
    width := i32(rl.GetScreenWidth())
    height := i32(rl.GetScreenHeight())
    mouse := rl.GetMousePosition()
    origin := [2]f32 {f32(width - height) / 2, 0}
    rl.ClearBackground(rl.BLACK)
    rl.DrawRectangleLines(i32(origin.x), i32(origin.y), height, height, rl.RAYWHITE)
    line_color := rl.Color { 100, 100, 100, 255 }
    nb_chunks: i32 = LEVEL_WIDTH / CHUNK_SIZE
    cell_width: i32 = height / nb_chunks
    cell_height: i32 = height / nb_chunks
    for i in 0..<GRID_WIDTH {
        rl.DrawLine(
            i32(origin.x), 
            cell_height * i32(i), 
            i32(origin.x) + cell_width * nb_chunks, 
            cell_height * i32(i), 
            line_color
        )
        rl.DrawLine(
            i32(origin.x) + cell_height * i32(i),
            0,
            i32(origin.x) + cell_height * i32(i),
            height,
            line_color
        )
    }
    mouse_on_map := [2]f32 {
        mouse.x - origin.x,
        mouse.y
    }
    mouse_square := [2]i32 {
        i32(mouse_on_map.x / f32(cell_width * nb_chunks) * f32(nb_chunks)),
        i32(mouse_on_map.y / f32(cell_height * nb_chunks) * f32(nb_chunks))
    }
    rl.DrawText(
        fmt.ctprintf("%d", mouse_square.x + mouse_square.y * nb_chunks),
        i32(origin.x) + mouse_square.x * cell_width + 5, i32(origin.y) + mouse_square.y * cell_height + 5, 
        5, rl.RAYWHITE)
    rl.DrawRectangleLinesEx(
        rl.Rectangle {
            origin.x + f32(mouse_square.x * cell_width),
            origin.y + f32(mouse_square.y * cell_height),
            f32(cell_width),
            f32(cell_height)
        },
        4, rl.RAYWHITE
    )
    ship_on_map := add_vectors(level_convert_pos_to_map(level.ship.position), origin)
    rl.DrawCircleV(ship_on_map, 5, rl.RAYWHITE)
    rl.DrawText("You", i32(ship_on_map.x + 5), i32(ship_on_map.y + 5), 5, rl.RAYWHITE)

    poi_color := rl.Color { 26, 188, 156, 255 }
    for poi, _ in level.pois {
        poi_position := add_vectors(level_convert_pos_to_map(poi.position), origin)
        rl.DrawCircleV(poi_position, 5, poi_color)
        poi_name: cstring = ""
        if poi.type == PoiType.Heal {
            poi_name = "Heal"
        }
        rl.DrawText(poi_name, i32(poi_position.x) + 5, i32(poi_position.y) + 5, 5, poi_color)
    }
}

level_convert_pos_to_map :: proc(position: [2]f32) -> [2]f32 {
    map_side := f32(rl.GetScreenHeight())
    return [2]f32 {
        position.x / LEVEL_WIDTH * map_side,
        position.y / LEVEL_HEIGHT * map_side
    }
}

add_vectors :: proc(v1, v2: [2]f32) -> [2]f32 {
    return [2]f32 {
        v1.x + v2.x,
        v1.y + v2.y
    }
}