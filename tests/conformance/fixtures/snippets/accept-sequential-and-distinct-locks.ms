# conform: tags=scope-cleanup,mutation,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
from "@std/shared.ms" import Shared, share
from "@std/sync.ms" import lock

export def main() -> Int:
    let a = share(1)
    let b = share(2)
    var one = lock(a)
    var two = lock(b)
    two.value += one.value
    one.close()

    var again = lock(a)
    again.value += 1
    again.close()
    return 0
