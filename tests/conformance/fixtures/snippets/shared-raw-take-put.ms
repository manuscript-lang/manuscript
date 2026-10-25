# conform: tags=diagnostics,stdlib-shared,tier-core
# conform: phase=check
from "@std/shared.ms" import Shared, share

def bump(box: Shared[List[Int]]) -> Unit:
    var items = box.take()
    items.append(1)
    box.put(items)
