package enums

import rl "vendor:raylib"

KAMIKAZE_COLOR :: rl.Color { 214, 48, 49, 255 }

BotType :: enum {
    Kamikaze = 0
}

bot_color :: proc(bot: BotType) -> rl.Color {
    switch bot {
        case BotType.Kamikaze: return KAMIKAZE_COLOR
    }
    return rl.RED
}