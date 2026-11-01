import share, lock from "@std/concurrency/shared.ms"

export fn main() Int:
    let box = share(1)
    var outer = lock(box)
    var inner = lock(box)
    inner.value += 1
    inner.close().get(none)
    outer.value += 1
    outer.close().get(none)
    return 0
