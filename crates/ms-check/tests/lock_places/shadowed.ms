import Shared, share from "@std/concurrency/shared.ms"
import lock from "@std/concurrency/sync.ms"

export fn main() Int:
    let box = share(1)
    var outer = lock(box)
    if true:
        let box = share(2)
        var inner = lock(box)
        inner.value += 1
    outer.value += 1
    return 0
