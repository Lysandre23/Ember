package models

import rl "vendor:raylib"
import "core:math"
import "core:math/rand"

PARTICLE_LIFETIME  :: 20
PARTICLE_SPEED_MIN :: 60.0
PARTICLE_SPEED_MAX :: 160.0
PARTICLE_RADIUS    :: 2.0

// Generic short-lived visual particle, owned by Level rather than any single
// entity, so any component (the ship's laser today, a bot colliding with a
// meteor tomorrow) can spawn a burst at an impact point without needing to
// know about — or duplicate — the particle system itself. Radius interpolates
// from start_radius down to end_radius over the particle's lifetime, so a
// caller can make it hold its size (start == end, what the laser sparks use)
// or pulse — pop in big and shrink away, which is what the ship trail uses.
Particle :: struct {
    position: [2]f32,
    speed: [2]f32,
    lifetime: int,
    max_lifetime: int,
    color: rl.Color,
    start_radius: f32,
    end_radius: f32,
}

particle_spawn_burst :: proc(particles: ^[dynamic]Particle, position: [2]f32, color: rl.Color, count: int, start_radius := f32(PARTICLE_RADIUS), end_radius := f32(PARTICLE_RADIUS)) {
    for _ in 0..<count {
        angle := rand.float32() * math.TAU
        speed := PARTICLE_SPEED_MIN + rand.float32() * (PARTICLE_SPEED_MAX - PARTICLE_SPEED_MIN)
        append(particles, Particle {
            position = position,
            speed = [2]f32 { math.cos(angle), math.sin(angle) } * speed,
            lifetime = PARTICLE_LIFETIME,
            max_lifetime = PARTICLE_LIFETIME,
            color = color,
            start_radius = start_radius,
            end_radius = end_radius,
        })
    }
}

particle_update :: proc(particles: ^[dynamic]Particle, dt: f32) {
    #reverse for &p, i in particles {
        p.lifetime -= 1
        if p.lifetime <= 0 {
            unordered_remove(particles, i)
            continue
        }
        p.position += p.speed * dt
    }
}

particle_render :: proc(particles: [dynamic]Particle) {
    for p in particles {
        t := f32(p.lifetime) / f32(p.max_lifetime)
        color := p.color
        color.a = u8(t * 255)
        radius := p.end_radius + (p.start_radius - p.end_radius) * t
        rl.DrawCircleV(p.position, radius, color)
    }
}
