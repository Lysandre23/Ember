package enums

import rl "vendor:raylib"

SAW_COLOR :: rl.Color { 223, 230, 233, 255 }
GUN_COLOR :: rl.Color { 255, 190, 90, 255 }

TurretType :: enum {
    Saw = 0,
    Gun,
}

turret_name :: proc(turret: TurretType) -> cstring {
    switch turret {
        case TurretType.Saw: return "Saw Drone"
        case TurretType.Gun: return "Gun Drone"
    }
    return ""
}

turret_color :: proc(turret: TurretType) -> rl.Color {
    switch turret {
        case TurretType.Saw: return SAW_COLOR
        case TurretType.Gun: return GUN_COLOR
    }
    return rl.RAYWHITE
}
