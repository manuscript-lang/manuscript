# conform: tags=diagnostics,mutation,stdlib-shared,tier-core
# conform: phase=check
import Shared from "@std/concurrency/shared.ms"

type Stats:
    hits: Int

export fn main() Int:
    let stats = Shared(Stats(hits: 0))
    stats.hits = 1
    return 0
