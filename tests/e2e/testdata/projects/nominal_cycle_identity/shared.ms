import Door from "./inner.ms"

type Pair[T]:
    first: T
    second: T

export fn exercise_shared(
    first: String,
    second: String,
    third: String,
    fourth: String
) Unit:
    let held = Pair(Pair(Door(first), Door(second)), Pair(Door(third), Door(fourth)))
    let _borrowed_path = held.first.first.path
