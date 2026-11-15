import promise from "@std/concurrency/promise.ms"

fn work() Int!:
    return ok(1)

fn main() Void:
    promise(fn: work())
