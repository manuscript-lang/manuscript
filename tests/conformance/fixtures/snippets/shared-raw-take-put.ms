# conform: tags=diagnostics,stdlib-shared,tier-core
# conform: phase=check
import {new_lock, Lock} from "@std/lock.ms"

fn bump(box: Lock[List[Int]]) Unit:
    var items = box.take()
    items.append(1)
    box.put(items)
