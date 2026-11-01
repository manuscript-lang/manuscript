# conform: tags=diagnostics,scope-cleanup,mutation,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
import Shared, share from "@std/concurrency/shared.ms"

export fn main() Int:
    let box = share(1)
    var outer = box.lock()
    var inner = box.lock()
    inner.value += 1
    outer.value += 1
    return 0
