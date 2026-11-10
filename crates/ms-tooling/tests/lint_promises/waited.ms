import promise from "@std/concurrency/promise.ms"

fn work() Int!:
    return ok(1)

export fn main() Int:
    p := promise(fn: work())
    n := p.wait().get(0)
    return n
