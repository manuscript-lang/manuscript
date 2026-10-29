import Data from "@std/core.ms"

type Point:
    x: Int
    y: Int

fn need[T: Data](value: T) Int:
    return 1

export fn main() Int:
    let grid = Map[Point, Int]()
    return need(grid)
