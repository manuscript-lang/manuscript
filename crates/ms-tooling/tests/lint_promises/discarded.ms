import promise from "@std/concurrency/promise.ms"

fn work() Int!:
    return ok(1)

fn main() Void:
    void promise(fn: work())
