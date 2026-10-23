import {max} from "@std/math.ms"

type Point:
    x: Int

export fn main() Int:
    let furthest = max(Point(x: 1), Point(x: 2))

    return furthest.x
