# conform: tags=scope-cleanup,mutation,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
import Shared from "@std/concurrency/shared.ms"

export fn main() Int:
    var a = Shared(1)
    var b = Shared(2)
    let first: Int = a
    b = first + 2
    a = first + 1
    let second: Int = b
    return second - 3
