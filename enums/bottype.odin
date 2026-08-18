package enums

import rl "vendor:raylib"

KAMIKAZE_COLOR :: rl.Color { 214, 48, 49, 255 }
KAMIKAZE_HEALTH :: 20

BotType :: enum {
    Kamikaze = 0
}

bot_color :: proc(bot: BotType) -> rl.Color {
    switch bot {
        case BotType.Kamikaze: return KAMIKAZE_COLOR
    }
    return rl.RED
}

bot_health :: proc(bot: BotType) -> f32 {
    switch bot {
        case BotType.Kamikaze: return KAMIKAZE_HEALTH
    }
    return 10
}