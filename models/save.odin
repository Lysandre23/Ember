package models

import "core:os"
import "core:strconv"
import "core:strings"

SAVE_FILE_PATH :: "ember_save.txt"

// The only thing persisted across executions right now: the deepest map
// tier ever reached (Game.best_score, bumped and re-saved the instant a run
// beats it — see game_update). A bare integer in a text file is all a
// single stat needs — no reach for a structured format like JSON over one
// number. Missing file or unparsable contents (first ever launch, a
// hand-edited/corrupt file) both just fall back to 0 rather than erroring.
save_load_best_score :: proc() -> int {
    data, err := os.read_entire_file(SAVE_FILE_PATH, context.temp_allocator)
    if err != nil {
        return 0
    }
    text := strings.trim_space(string(data))
    value, ok := strconv.parse_int(text)
    if !ok {
        return 0
    }
    return value
}

save_write_best_score :: proc(score: int) {
    buf: [20]u8
    text := strconv.write_int(buf[:], i64(score), 10)
    _ = os.write_entire_file(SAVE_FILE_PATH, text)
}
