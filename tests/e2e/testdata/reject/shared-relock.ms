import new_lock from "@std/lock.ms"

export fn main() Int:
    let box = new_lock(1)
    var outer = box.lock()
    var inner = box.lock()
    inner.value += 1
    inner.close()
    outer.value += 1
    outer.close()
    return 0
