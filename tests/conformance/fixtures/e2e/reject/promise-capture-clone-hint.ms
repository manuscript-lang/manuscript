// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
import Promise, promise from "@std/concurrency/promise.ms"

fn later() fn() Promise[Int]:
    xs := [1, 2, 3]
    return () => promise(() => ok(xs.length()))
