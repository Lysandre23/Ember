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

BOT_FIRST_WAVE_DELAY     :: 60.0 // grace period before any bot shows up at all, so the player has time to buy a first turret
BOT_SPAWN_INTERVAL_START :: 6.0
BOT_SPAWN_INTERVAL_MIN   :: 1.5
BOT_WAVE_SIZE_START      :: 5
BOT_WAVE_SIZE_MAX        :: 18
BOT_MAX_ALIVE            :: 90
BOT_DIFFICULTY_RAMP      :: 30.0 // seconds survived per extra bot / interval second shaved off

// mining_alert (0..1, see Ship's MINING_ALERT_GAIN and ship_update) rides on
// top of the time-based ramp above: sitting still lasering a rare (gold/
// osmium) meteor is what's supposed to summon a real swarm, on top of
// whatever the base ambient spawn rate already is.
MINING_ALERT_DECAY        :: 0.1  // per second, once the player stops feeding it
BOT_ALERT_INTERVAL_BONUS  :: 4.0  // shaved off the spawn interval at full alert
BOT_ALERT_WAVE_BONUS      :: 10   // extra bots per wave at full alert



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
    particles         : [dynamic]Particle,
    pause             : bool,
    display_map       : bool,
    time_survived     : f32,
    bot_spawn_timer   : f32,
    mining_alert      : f32,
    bullets           : [dynamic]Bullet,

    // Shop (models/shop.odin): shop_open drives level.pause the same way
    // display_map does, and shop_dismissed keeps a Leave'd shop from
    // re-triggering while the ship is still parked on the same poi.
    shop_open      : bool,
    shop_dismissed : bool,
    cards_pending  : bool,
    card_offers    : [2]enums.TurretType,
}

level_create :: proc(level: ^Level) {
    level.camera = rl.Camera2D {
        target   = level.ship.position,
        offset   = { f32(rl.GetScreenWidth()) / 2, (f32(rl.GetScreenHeight()) - HUD_BAR_HEIGHT) / 2 },
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

    level.bot_spawn_timer = BOT_FIRST_WAVE_DELAY

    initial_chunk := get_chunk_index(level.ship.position.x, level.ship.position.y)
    level.last_player_chunk = initial_chunk
    populate_active_zone(level, initial_chunk)

    level_spawn_poi(level, HEAL_POI_NUMBER, PoiType.Heal)
    level_spawn_poi(level, SHOP_POI_NUMBER, PoiType.Shop)
}

level_update :: proc(level: ^Level, dt: f32) {
    level.display_map = rl.IsKeyDown(.TAB)
    level.pause = level.display_map || level.shop_open

    if level.pause {
        return
    }

    new_meteors: [dynamic]Meteor
    destroyed_meteor_ids: [dynamic]int
    defer delete(new_meteors)
    defer delete(destroyed_meteor_ids)

    ship_update(&level.ship, level.meteors.items[:], level.active_meteors[:], &new_meteors, &destroyed_meteor_ids, level.bots.items[:], level.active_bots[:], &level.particles, &level.mining_alert, level.camera, dt)
    particle_update(&level.particles, dt)

    level.time_survived += dt
    level.mining_alert = max(0, level.mining_alert - MINING_ALERT_DECAY * dt)
    level_update_bot_spawning(level, dt)
    turrets_update(level, dt)

    for id in destroyed_meteor_ids {
        old_chunk := get_chunk_index(level.meteors.items[id].position.x, level.meteors.items[id].position.y)
        meteor_destroy(&level.meteors.items[id])
        remove_id_from_slice(&level.chunks[old_chunk].meteors, id)
        remove_id_from_slice(&level.active_meteors, id)
        pool_remove(&level.meteors, id)
    }

    for fragment in new_meteors {
        id := pool_add(&level.meteors, fragment)
        chunk_idx := get_chunk_index(fragment.position.x, fragment.position.y)
        append(&level.chunks[chunk_idx].meteors, id)
        if is_chunk_active(level, chunk_idx) {
            append(&level.active_meteors, id)
        }
    }

    for &poi in level.pois {
        poi_update(&poi, &level.ship, dt)
    }
    level_update_shop_trigger(level)

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
        if bot.dead {
            continue
        }
        bot_render(bot, level.ship)
    }
    turrets_render(level^)
    particle_render(level.particles)
}

level_spawn_bot :: proc(level: ^Level, position: [2]f32, type: enums.BotType = enums.BotType.Kamikaze) {
    bot_data := Bot {
        dead      = false,
        type      = type,
        position  = position,
        direction = 0,
        health    = enums.bot_health(type),
    }
    bot_id := pool_add(&level.bots, bot_data)
    bot_chunk_idx := get_chunk_index(position.x, position.y)
    append(&level.chunks[bot_chunk_idx].bots, bot_id)
    if is_chunk_active(level, bot_chunk_idx) {
        append(&level.active_bots, bot_id)
    }
}

// Kamikazes have no pathfinding — a player who plays it smart can bait them
// into meteors — so the only real pressure they apply is volume. Waves get
// bigger and closer together the longer the player survives (BOT_DIFFICULTY_RAMP),
// and mining_alert (fed by ship_update while lasering a rare meteor, see
// MINING_ALERT_GAIN) stacks a second, faster-moving bonus on top — sitting
// still to mine gold/osmium is meant to summon a real swarm. Both are capped
// by BOT_MAX_ALIVE so a player who successfully evades a swarm doesn't end up
// dragging an ever-growing, uncapped trail behind them.
level_update_bot_spawning :: proc(level: ^Level, dt: f32) {
    level.bot_spawn_timer -= dt
    if level.bot_spawn_timer > 0 {
        return
    }

    difficulty := level.time_survived / BOT_DIFFICULTY_RAMP
    interval := BOT_SPAWN_INTERVAL_START - difficulty - level.mining_alert * BOT_ALERT_INTERVAL_BONUS
    level.bot_spawn_timer = max(BOT_SPAWN_INTERVAL_MIN, interval)

    alive := len(level.bots.items) - len(level.bots.free_indices)
    if alive >= BOT_MAX_ALIVE {
        return
    }

    wave_size := BOT_WAVE_SIZE_START + int(difficulty) + int(level.mining_alert * BOT_ALERT_WAVE_BONUS)
    wave_size = min(BOT_WAVE_SIZE_MAX, wave_size)
    to_spawn := min(wave_size, BOT_MAX_ALIVE - alive)

    spawn_dist := utils.norm_vec2([2]f32 {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}) + 200

    for _ in 0..<to_spawn {
        angle := rand.float32() * math.TAU
        position := level.ship.position + [2]f32 {math.cos(angle), math.sin(angle)} * spawn_dist
        position.x = clamp(position.x, 0, LEVEL_WIDTH)
        position.y = clamp(position.y, 0, LEVEL_HEIGHT)
        level_spawn_bot(level, position)
    }
}

level_spawn_poi :: proc(level: ^Level, n: int, type: PoiType) {
    for i in 0..<n {
        can_place := false
        count := 0
        for !can_place && count < 15 {
            position := [2]f32 {rand.float32() * LEVEL_WIDTH, rand.float32() * LEVEL_HEIGHT}
            acceptable := true

            for poi in level.pois {
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
        }
    }
}

level_render_map :: proc(hud: Hud, level: Level) {
    width := i32(rl.GetScreenWidth())
    height := i32(rl.GetScreenHeight())
    map_side := f32(height)
    mouse := rl.GetMousePosition()
    origin := [2]f32 {f32(width - height) / 2, 0}

    rl.ClearBackground(rl.Color { 8, 8, 14, 255 })
    rl.DrawRectangleLinesEx(rl.Rectangle { origin.x, origin.y, map_side, map_side }, 2, rl.Color { 255, 255, 255, 120 })

    line_color := rl.Color { 255, 255, 255, 30 }
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
    if mouse_square.x >= 0 && mouse_square.x < nb_chunks && mouse_square.y >= 0 && mouse_square.y < nb_chunks {
        rl.DrawRectangleLinesEx(
            rl.Rectangle {
                origin.x + f32(mouse_square.x * cell_width),
                origin.y + f32(mouse_square.y * cell_height),
                f32(cell_width),
                f32(cell_height)
            },
            3, rl.Color { 255, 255, 255, 160 }
        )
        rl.DrawTextEx(
            hud.font,
            fmt.ctprintf("SECTOR %d", mouse_square.x + mouse_square.y * nb_chunks),
            [2]f32 { origin.x + f32(mouse_square.x * cell_width) + 6, origin.y + f32(mouse_square.y * cell_height) + 6 },
            14, 1, rl.Color { 255, 255, 255, 200 }
        )
    }

    poi_color := rl.Color { 26, 188, 156, 255 }
    for poi, _ in level.pois {
        poi_position := add_vectors(level_convert_pos_to_map(poi.position, map_side), origin)
        rl.DrawCircleV(poi_position, 5, poi_color)
        poi_name: cstring = ""
        if poi.type == PoiType.Heal {
            poi_name = "Heal"
        } else if poi.type == PoiType.Shop {
            poi_name = "Shop"
        }
        rl.DrawTextEx(hud.font, poi_name, [2]f32 { poi_position.x + 8, poi_position.y - 4 }, 12, 1, poi_color)
    }

    ship_on_map := add_vectors(level_convert_pos_to_map(level.ship.position, map_side), origin)
    rl.DrawCircleV(ship_on_map, 6, rl.RAYWHITE)
    rl.DrawTextEx(hud.font, "You", [2]f32 { ship_on_map.x + 8, ship_on_map.y - 4 }, 14, 1, rl.RAYWHITE)

    rl.DrawTextEx(hud.font, "SYSTEM MAP", [2]f32 { origin.x + 10, origin.y + map_side - 26 }, 16, 1, rl.Color { 255, 255, 255, 150 })
}

level_render_minimap :: proc(hud: Hud, level: Level, origin: [2]f32, size: f32) {
    bounds := rl.Rectangle { origin.x, origin.y, size, size }

    rl.DrawRectangleRounded(bounds, 0.1, 6, rl.Color { 20, 20, 28, 220 })
    rl.DrawRectangleRoundedLinesEx(bounds, 0.1, 6, 1.5, rl.Color { 255, 255, 255, 60 })

    nb_chunks: i32 = LEVEL_WIDTH / CHUNK_SIZE
    cell := size / f32(nb_chunks)
    grid_color := rl.Color { 255, 255, 255, 20 }
    for i in 1..<int(nb_chunks) {
        offset := f32(i) * cell
        rl.DrawLineV([2]f32 { origin.x + offset, origin.y }, [2]f32 { origin.x + offset, origin.y + size }, grid_color)
        rl.DrawLineV([2]f32 { origin.x, origin.y + offset }, [2]f32 { origin.x + size, origin.y + offset }, grid_color)
    }

    poi_color := rl.Color { 26, 188, 156, 255 }
    for poi, _ in level.pois {
        p := add_vectors(level_convert_pos_to_map(poi.position, size), origin)
        rl.DrawCircleV(p, 2, poi_color)
    }

    ship_on_map := add_vectors(level_convert_pos_to_map(level.ship.position, size), origin)
    rl.DrawCircleV(ship_on_map, 3, rl.RAYWHITE)

    rl.DrawTextEx(hud.font, "MAP", [2]f32 { origin.x + 6, origin.y + 4 }, 11, 1, rl.Color { 255, 255, 255, 130 })
}

level_convert_pos_to_map :: proc(position: [2]f32, map_side: f32) -> [2]f32 {
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