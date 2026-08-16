package models

Pool :: struct($T: typeid) {
    items:        [dynamic]T,
    free_indices: [dynamic]int,
}

pool_add :: proc(pool: ^Pool($T), data: T) -> int {
    id: int
    if len(pool.free_indices) > 0 {
        id = pop(&pool.free_indices)
        pool.items[id] = data
    } else {
        id = len(pool.items)
        append(&pool.items, data)
    }
    return id
}

pool_remove :: proc(pool: ^Pool($T), id: int) {
    append(&pool.free_indices, id)
}