# conform: tags=with-cleanup,mutation,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
from "@std/shared.ms" import Shared, share
from "@std/sync.ms" import lock
export def main() -> Int:
    let a = share(1)
    let b = share(2)
    with var one = lock(a):
        with var two = lock(b):
            two.value += one.value
    with var again = lock(a):
        again.value += 1
    return 0
