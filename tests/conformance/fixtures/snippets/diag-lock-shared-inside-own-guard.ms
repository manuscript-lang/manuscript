# conform: tags=diagnostics,scope-cleanup,mutation,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
import {new_lock, Lock} from "@std/lock.ms"

export fn main() Int:
    let box = new_lock(1)
    var outer = box.lock()
    var inner = box.lock()
    inner.value += 1
    outer.value += 1
    return 0
