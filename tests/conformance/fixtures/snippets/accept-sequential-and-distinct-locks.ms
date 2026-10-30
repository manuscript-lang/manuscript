# conform: tags=scope-cleanup,mutation,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
import {new_lock, Lock} from "@std/lock.ms"

export fn main() Int:
    let a = new_lock(1)
    let b = new_lock(2)
    var one = a.lock()
    var two = b.lock()
    two.value += one.value
    one.close()

    var again = a.lock()
    again.value += 1
    again.close()
    return 0
