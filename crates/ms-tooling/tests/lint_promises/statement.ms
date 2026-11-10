import promise from "@std/concurrency/promise.ms"

fn work() Int!:
    return ok(1)

fn main() Unit:
    promise(fn: work())
