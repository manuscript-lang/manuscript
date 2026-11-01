import share from "@std/concurrency/shared.ms"

export fn main() Int:
    let box = share(1)
    var outer = box.lock()
    var inner = box.lock()
    inner.value += 1
    inner.close().get(none)
    outer.value += 1
    outer.close().get(none)
    return 0
