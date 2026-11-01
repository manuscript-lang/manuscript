# conform: tags=diagnostics,stdlib-shared,tier-core
# conform: phase=check
import Shared, share from "@std/concurrency/shared.ms"

fn bump(box: Shared[List[Int]]) Unit:
    var items = box.take()
    items.append(1)
    box.put(items)
