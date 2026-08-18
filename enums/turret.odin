package enums

import rl "vendor:raylib"

SAW_COLOR    :: rl.Color { 223, 230, 233, 255 }
GUN_COLOR    :: rl.Color { 255, 190, 90, 255 }
// Electric cyan for the strike drone — kept distinct from the gun's warm
// tracer color and the bots' red/violet so it reads clearly as "friendly"
// under the CRT glow shader.
STRIKE_COLOR :: rl.Color { 0, 255, 214, 255 }

TurretType :: enum {
    Saw = 0,
    Gun,
    Strike,
}

turret_name :: proc(turret: TurretType) -> cstring {
    switch turret {
        case TurretType.Saw: return "Saw Drone"
        case TurretType.Gun: return "Gun Drone"
        case TurretType.Strike: return "Strike Drone"
    }
    return ""
}

turret_color :: proc(turret: TurretType) -> rl.Color {
    switch turret {
        case TurretType.Saw: return SAW_COLOR
        case TurretType.Gun: return GUN_COLOR
        case TurretType.Strike: return STRIKE_COLOR
    }
    return rl.RAYWHITE
}
