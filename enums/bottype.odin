package enums

import rl "vendor:raylib"

KAMIKAZE_COLOR :: rl.Color { 214, 48, 49, 255 }
KAMIKAZE_HEALTH :: 20

// Neon violet so it reads as a distinct threat from the kamikaze's red under
// the CRT glow shader (utils.CRT_SHADER) — bright, saturated colors are what
// actually bloom under that shader's threshold.
SNIPER_COLOR :: rl.Color { 155, 89, 182, 255 }
SNIPER_HEALTH :: 34

BotType :: enum {
    Kamikaze = 0,
    Sniper,
}

bot_color :: proc(bot: BotType) -> rl.Color {
    switch bot {
        case BotType.Kamikaze: return KAMIKAZE_COLOR
        case BotType.Sniper: return SNIPER_COLOR
    }
    return rl.RED
}

bot_health :: proc(bot: BotType) -> f32 {
    switch bot {
        case BotType.Kamikaze: return KAMIKAZE_HEALTH
        case BotType.Sniper: return SNIPER_HEALTH
    }
    return 10
}