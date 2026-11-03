import promise from "@std/concurrency/promise.ms"

fn work() Int!:
    return ok(1)

export fn main() Int:
    promise(fn: work())
    return 0
