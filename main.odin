package ember

import "models"

main :: proc() {
    game: models.Game
    models.game_init(&game)
    models.game_run(&game)
}