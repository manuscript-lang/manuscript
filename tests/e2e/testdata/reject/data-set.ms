import Data from "@std/core.ms"

fn need[T: Data](value: T) Int:
    return 1

export fn main() Int:
    let ids = Set[Int]()
    return need(ids)
