# conform: tags=diagnostics,stdlib-shared,tier-core
# conform: phase=check
import Shared, take, put from "@std/concurrency/shared.ms"

fn bump(box: Shared[List[Int]]) Unit:
    var items = take(box)
    items.append(1)
    put(box, items)
