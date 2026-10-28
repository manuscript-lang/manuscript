# conform: tags=diagnostics,with-cleanup,mutation,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
import {Shared, share} from "@std/shared.ms"
import lock from "@std/sync.ms"

export fn main() Int:
    let box = share(1)

    with var outer = lock(box):
        with var inner = lock(box):
            inner.value += 1
        outer.value += 1

    return 0
