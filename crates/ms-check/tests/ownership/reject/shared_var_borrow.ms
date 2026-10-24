import {share, Shared} from "@std/shared.ms"

fn f() Int:
    let items = share([1, 2])
    var inner = items.get()  # error: read-only result
    return inner.length()
