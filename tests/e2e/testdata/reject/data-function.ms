import Data from "@std/core.ms"

type Handler:
    name: String
    run: fn() Int

fn need[T: Data](value: T) Int:
    return 1

export fn main() Int:
    return need(Handler("h", fn() Int: 1))
