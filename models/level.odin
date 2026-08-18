package models

import "../enums"
import "../utils"
import "core:math"
import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"

METEOR_IN_LEVEL       :: 700
CAMERA_LERP_SPEED     :: 5.0
CHUNK_SIZE            :: 1000.0
GRID_WIDTH            :: 10
GRID_HEIGHT           :: 10
LEVEL_WIDTH           :: 10000
LEVEL_HEIGHT          :: 10000
HEAL_POI_NUMBER       :: 6
MIN_RANGE_BETWEEN_POI :: 3000

// Base pressure for map_tier 1 — deliberately gentle (a new run should not
// feel like a swarm from minute one). Each extraction jump (level_advance_map
// below) raises map_tier, and BOT_TIER_* constants add on top of these bases
// so later maps genuinely escalate instead of every map starting at the same
// difficulty. See level_update_bot_spawning for how they combine.
BOT_FIRST_WAVE_DELAY     :: 60.0 // grace period before any bot shows up at all, so the player has time to buy a first turret
BOT_SPAWN_INTERVAL_START :: 6.0
BOT_SPAWN_INTERVAL_MIN   :: 1.5
BOT_WAVE_SIZE_START      :: 4
BOT_WAVE_SIZE_MAX        :: 14
BOT_MAX_ALIVE            :: 40
BOT_DIFFICULTY_RAMP      :: 40.0 // seconds survived (within one map) per extra bot / interval second shaved off

BOT_TIER_DIFFICULTY_STEP :: 1.5  // added to the difficulty scalar per map beyond the first — same units as time_survived/BOT_DIFFICULTY_RAMP
BOT_TIER_WAVE_MAX_BONUS  :: 6    // added to the wave-size cap per map beyond the first
BOT_TIER_MAX_ALIVE_BONUS :: 25   // added to the alive cap per map beyond the first

SNIPER_SPAWN_CHANCE_BASE     :: 0.1 // fraction of spawns that are snipers on map_tier 1
SNIPER_SPAWN_CHANCE_PER_TIER :: 0.05
SNIPER_SPAWN_CHANCE_MAX      :: 0.5

// mining_alert (0..1, see Ship's MINING_ALERT_GAIN and ship_update) rides on
// top of the time-based ramp above: sitting still lasering a rare (gold/
// osmium) meteor is what's supposed to summon a real swarm, on top of
// whatever the base ambient spawn rate already is.
MINING_ALERT_DECAY        :: 0.1  // per second, once the player stops feeding it
BOT_ALERT_INTERVAL_BONUS  :: 4.0  // shaved off the spawn interval at full alert
BOT_ALERT_WAVE_BONUS      :: 14   // extra bots per wave at full alert



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
    enemy_bullets     : [dynamic]Bullet,
    // One slot per possible strike-drone level (TURRET_MAX_LEVEL, see
    // shop.odin) — only the first ship.turret_levels[Strike] entries are
    // active, mirroring how saw_update grows blade count with level.
    drones            : [TURRET_MAX_LEVEL]Drone,
    camera_shake      : f32,

    // Which map/run-depth this is — starts at 1, incremented by
    // level_advance_map (below) each time the player takes an extraction
    // point. Drives bot strength/pressure scaling (see
    // level_update_bot_spawning and models/bot.odin's bot_tier_multiplier).
    map_tier : int,

    // Shop (models/shop.odin): shop_open drives level.pause the same way
    // display_map does, and shop_dismissed keeps a Leave'd shop from
    // re-triggering while the ship is still parked on the same poi.
    shop_open      : bool,
    shop_dismissed : bool,
    cards_pending  : bool,
    card_offers    : [2]enums.TurretType,

    // Extraction (models/extract.odin): same open/dismissed pattern as the
    // shop, so docking on the beacon offers a choice instead of instantly
    // warping the ship.
    extract_open      : bool,
    extract_dismissed : bool,
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

    for i in 0..<TURRET_MAX_LEVEL {
        level.drones[i].position = level.ship.position
        for j in 0..<DRONE_TRAIL_SEGMENTS {
            level.drones[i].trail[j] = level.ship.position
        }
    }

    initial_chunk := get_chunk_index(level.ship.position.x, level.ship.position.y)
    level.last_player_chunk = initial_chunk
    level.chunks[initial_chunk].visited = true
    populate_active_zone(level, initial_chunk)

    level_spawn_poi(level, HEAL_POI_NUMBER, PoiType.Heal)
    level_spawn_poi(level, SHOP_POI_NUMBER, PoiType.Shop)
    level_spawn_extract_pois(level)
}

// Frees everything the current map owns and rebuilds a brand new one around
// `ship` at the given map_tier. Shared by game_init/game_restart (a brand
// new ship, tier 1) and level_advance_map below (the same ship carried over,
// tier+1) so there's exactly one place that knows how to (re)build a map.
level_reset :: proc(level: ^Level, ship: Ship, tier: int) {
    for &meteor in level.meteors.items {
        meteor_destroy(&meteor)
    }
    delete(level.meteors.items)
    delete(level.meteors.free_indices)
    delete(level.bots.items)
    delete(level.bots.free_indices)
    for &chunk in level.chunks {
        delete(chunk.meteors)
        delete(chunk.bots)
    }
    delete(level.active_meteors)
    delete(level.active_bots)
    delete(level.pois)
    delete(level.particles)
    delete(level.bullets)
    delete(level.enemy_bullets)

    level^ = Level {}
    level.ship = ship
    level.map_tier = tier
    level_create(level)
}

// Called when the player confirms a jump at an extraction point
// (models/extract.odin). The ship — position, upgrades, turret levels,
// stocks, all of it — carries over unchanged into the new map except for a
// fresh spawn point; only the surrounding world (meteors, bots, POIs) and
// the difficulty tier reset/advance.
level_advance_map :: proc(level: ^Level) {
    ship := level.ship
    ship.position = [2]f32 {
        LEVEL_WIDTH * (rand.float32() * 0.8 + 0.2),
        LEVEL_HEIGHT * (rand.float32() * 0.8 + 0.2),
    }
    level_reset(level, ship, level.map_tier + 1)
}

level_update :: proc(level: ^Level, dt: f32) {
    level.display_map = rl.IsKeyDown(.TAB)
    level.pause = level.display_map || level.shop_open || level.extract_open

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
    drone_update(level, dt)
    enemy_bullets_update(level, dt)

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
    level_update_extract_trigger(level)

    player_chunk := get_chunk_index(level.ship.position.x, level.ship.position.y)
    level.chunks[player_chunk].visited = true
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

        bot_update(bot, level, dt)

        if bot.dead {
            bot_explode(level, bot.position, bot.type)
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

    // Trauma-style shake: bot_explode adds a small amount per kill (capped
    // at SHAKE_MAX so a big simultaneous cluster of kills doesn't spike into
    // an earthquake) and it bleeds off every frame, so a single kill barely
    // registers but a dense swarm dying together reads as a real impact.
    level.camera_shake = max(0, level.camera_shake - SHAKE_DECAY * dt)
    base_offset := [2]f32 {f32(rl.GetScreenWidth()) / 2, (f32(rl.GetScreenHeight()) - HUD_BAR_HEIGHT) / 2}
    shake_jitter := [2]f32 {rand.float32() * 2 - 1, rand.float32() * 2 - 1} * level.camera_shake
    level.camera.offset = base_offset + shake_jitter
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
    drone_render(level^)
    enemy_bullets_render(level.enemy_bullets)
    particle_render(level.particles)
}

// Meteors used to only ever be damaged from one place (the ship's laser, via
// ship_update's out-params). Now bots ram them and the strike drone passes
// through them too (models/bot.odin, models/drone.odin), so this is the
// shared entry point that applies a one-off impact to whichever active
// meteor a movement segment crosses and immediately folds in the result —
// pool/chunk bookkeeping for a destroyed meteor or a split's fragments,
// mirroring exactly what level_update already does for the ship's laser.
// Only one meteor is ever hit per call (the loop returns on the first hit),
// so mutating level.active_meteors mid-iteration is safe.
METEOR_IMPACT_BROADPHASE_MARGIN :: 20

level_meteor_impact :: proc(level: ^Level, from, to: [2]f32, damage: f32) -> (impact: [2]f32, meteor_material: enums.Materials, hit: bool) {
    for id in level.active_meteors {
        meteor := &level.meteors.items[id]

        // Cheap circle reject before meteor_hit's exact per-cell-edge test —
        // this runs for every moving bot/drone every frame, so skipping
        // meteors nowhere near the segment matters.
        if utils.vec2_point_segment_dist(meteor.position, from, to) > meteor.avoid_radius + METEOR_IMPACT_BROADPHASE_MARGIN {
            continue
        }

        hit_impact, _, fragments, destroyed, did_hit := meteor_hit_impact(meteor, from, to, damage)
        if !did_hit {
            continue
        }

        impact = hit_impact
        meteor_material = meteor.material
        hit = true

        if destroyed {
            old_chunk := get_chunk_index(meteor.position.x, meteor.position.y)
            meteor_destroy(meteor)
            remove_id_from_slice(&level.chunks[old_chunk].meteors, id)
            remove_id_from_slice(&level.active_meteors, id)
            pool_remove(&level.meteors, id)
        }

        for fragment in fragments {
            frag_id := pool_add(&level.meteors, fragment)
            chunk_idx := get_chunk_index(fragment.position.x, fragment.position.y)
            append(&level.chunks[chunk_idx].meteors, frag_id)
            if is_chunk_active(level, chunk_idx) {
                append(&level.active_meteors, frag_id)
            }
        }
        delete(fragments)
        return
    }
    return
}

// Simple circle test (against each active meteor's avoid_radius) used to
// block player/enemy gun bullets on meteors — solid rock stops a bullet,
// unlike the finer per-cell-edge test level_meteor_impact does for things
// that actually mine the rock.
level_point_in_any_meteor :: proc(level: Level, position: [2]f32) -> bool {
    for id in level.active_meteors {
        meteor := level.meteors.items[id]
        if utils.vec2_dist(position, meteor.position) < meteor.avoid_radius {
            return true
        }
    }
    return false
}

level_spawn_bot :: proc(level: ^Level, position: [2]f32, type: enums.BotType = enums.BotType.Kamikaze) {
    bot_data := Bot {
        dead      = false,
        type      = type,
        position  = position,
        direction = 0,
        health    = enums.bot_health(type) * bot_tier_multiplier(level^, BOT_TIER_HEALTH_MULT),
    }
    if type == enums.BotType.Sniper {
        // Randomized reload offset and a fixed strafe side, so a batch of
        // snipers spawned together don't all fire in lockstep or strafe in
        // a synchronized wall.
        bot_data.fire_reload = rand.float32() * SNIPER_FIRE_INTERVAL
        bot_data.strafe_sign = rand.float32() < 0.5 ? -1 : 1
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
// bigger and closer together the longer the player survives within this map
// (BOT_DIFFICULTY_RAMP), and mining_alert (fed by ship_update while lasering
// a rare meteor, see MINING_ALERT_GAIN) stacks a second, faster-moving bonus
// on top — sitting still to mine gold/osmium is meant to summon a real
// swarm. On top of that, map_tier (bumped by level_advance_map each time the
// player extracts) raises both the difficulty scalar and the wave/alive
// caps, so a fresh map starts under real pressure rather than every map
// beginning at the same baseline. Both wave size and alive count are capped
// so a player who successfully evades a swarm doesn't end up dragging an
// ever-growing, uncapped trail behind them.
level_update_bot_spawning :: proc(level: ^Level, dt: f32) {
    level.bot_spawn_timer -= dt
    if level.bot_spawn_timer > 0 {
        return
    }

    tier := level.map_tier - 1
    difficulty := level.time_survived / BOT_DIFFICULTY_RAMP + f32(tier) * BOT_TIER_DIFFICULTY_STEP
    interval := BOT_SPAWN_INTERVAL_START - difficulty - level.mining_alert * BOT_ALERT_INTERVAL_BONUS
    level.bot_spawn_timer = max(BOT_SPAWN_INTERVAL_MIN, interval)

    max_alive := BOT_MAX_ALIVE + tier * BOT_TIER_MAX_ALIVE_BONUS
    alive := len(level.bots.items) - len(level.bots.free_indices)
    if alive >= max_alive {
        return
    }

    wave_cap := BOT_WAVE_SIZE_MAX + tier * BOT_TIER_WAVE_MAX_BONUS
    wave_size := BOT_WAVE_SIZE_START + int(difficulty) + int(level.mining_alert * BOT_ALERT_WAVE_BONUS)
    wave_size = min(wave_cap, wave_size)
    to_spawn := min(wave_size, max_alive - alive)

    spawn_dist := utils.norm_vec2([2]f32 {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}) + 200
    sniper_chance := clamp(SNIPER_SPAWN_CHANCE_BASE + f32(tier) * SNIPER_SPAWN_CHANCE_PER_TIER, 0, SNIPER_SPAWN_CHANCE_MAX)

    for _ in 0..<to_spawn {
        angle := rand.float32() * math.TAU
        position := level.ship.position + [2]f32 {math.cos(angle), math.sin(angle)} * spawn_dist
        position.x = clamp(position.x, 0, LEVEL_WIDTH)
        position.y = clamp(position.y, 0, LEVEL_HEIGHT)
        bot_type := rand.float32() < sniper_chance ? enums.BotType.Sniper : enums.BotType.Kamikaze
        level_spawn_bot(level, position, bot_type)
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

    visited_color := rl.Color { 60, 130, 110, 70 }
    for row in 0..<GRID_HEIGHT {
        for col in 0..<GRID_WIDTH {
            if !level.chunks[row * GRID_WIDTH + col].visited {
                continue
            }
            rl.DrawRectangleRec(
                rl.Rectangle {
                    origin.x + f32(col * int(cell_width)),
                    origin.y + f32(row * int(cell_height)),
                    f32(cell_width), f32(cell_height)
                },
                visited_color
            )
        }
    }

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
        color := poi_color
        poi_name: cstring = ""
        if poi.type == PoiType.Heal {
            poi_name = "Heal"
        } else if poi.type == PoiType.Shop {
            poi_name = "Shop"
        } else if poi.type == PoiType.Extract {
            // Amber instead of the shared teal so the goal stands out from
            // ordinary Heal/Shop stops rather than blending into them.
            poi_name = "Extract"
            color = EXTRACT_COLOR
        }
        rl.DrawCircleV(poi_position, 5, color)
        rl.DrawTextEx(hud.font, poi_name, [2]f32 { poi_position.x + 8, poi_position.y - 4 }, 12, 1, color)
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

    visited_color := rl.Color { 60, 130, 110, 90 }
    for row in 0..<GRID_HEIGHT {
        for col in 0..<GRID_WIDTH {
            if !level.chunks[row * GRID_WIDTH + col].visited {
                continue
            }
            rl.DrawRectangleRec(
                rl.Rectangle { origin.x + f32(col) * cell, origin.y + f32(row) * cell, cell, cell },
                visited_color
            )
        }
    }

    grid_color := rl.Color { 255, 255, 255, 20 }
    for i in 1..<int(nb_chunks) {
        offset := f32(i) * cell
        rl.DrawLineV([2]f32 { origin.x + offset, origin.y }, [2]f32 { origin.x + offset, origin.y + size }, grid_color)
        rl.DrawLineV([2]f32 { origin.x, origin.y + offset }, [2]f32 { origin.x + size, origin.y + offset }, grid_color)
    }

    poi_color := rl.Color { 26, 188, 156, 255 }
    for poi, _ in level.pois {
        p := add_vectors(level_convert_pos_to_map(poi.position, size), origin)
        rl.DrawCircleV(p, 2, poi.type == PoiType.Extract ? EXTRACT_COLOR : poi_color)
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