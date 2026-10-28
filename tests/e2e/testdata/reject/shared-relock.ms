from "@std/shared.ms" import share
from "@std/sync.ms" import lock

export def main() -> Int:
    let box = share(1)
    var outer = lock(box)
    var inner = lock(box)
    inner.value += 1
    inner.close()
    outer.value += 1
    outer.close()
    return 0
