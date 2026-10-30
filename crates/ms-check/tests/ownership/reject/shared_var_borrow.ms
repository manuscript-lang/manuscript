import {new_lock, Lock} from "@std/lock.ms"

fn f() Int:
    let items = new_lock([1, 2])
    var inner = items.get()  # error: read-only result
    return inner.length()
