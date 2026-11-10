import Data from "@std/core.ms"

fn need[T: Data](value: T) Int:
    return 1

export fn main() Int:
    scores := Map[String, Int]()
    return need(scores) - 1
