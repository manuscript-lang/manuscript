# conform: tags=scope-cleanup,mutation,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
import Shared, share from "@std/concurrency/shared.ms"

export fn main() Int:
    let a = share(1)
    let b = share(2)
    var one = a.lock()
    var two = b.lock()
    two.value += one.value
    one.close().get(none)

    var again = a.lock()
    again.value += 1
    again.close().get(none)
    return 0
