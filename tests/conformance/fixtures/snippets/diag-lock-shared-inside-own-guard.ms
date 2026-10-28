# conform: tags=diagnostics,scope-cleanup,mutation,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
from "@std/shared.ms" import Shared, share
from "@std/sync.ms" import lock
export def main() -> Int:
    let box = share(1)
    var outer = lock(box)
    var inner = lock(box)
    inner.value += 1
    outer.value += 1
    return 0
