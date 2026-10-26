from "@std/shared.ms" import share
from "@std/sync.ms" import lock

export def main() -> Int:
    let box = share(1)

    with var outer = lock(box):
        with var inner = lock(box):
            inner.value += 1
        outer.value += 1

    return 0
