// conform: tags=diagnostics,tier-core
// conform: phase=check
import promise from "@std/concurrency/promise.ms"

fn compute() Int:
    return 1

export fn main() Int!:
    p := promise(() => compute())
    print(p.wait()?)
    return 0
