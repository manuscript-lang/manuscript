import Data from "@std/core.ms"

fn need[T: Data](value: T) Int:
    return 1

export fn main() Int:
    let scores = Map[Int, String]()
    return need(scores)
