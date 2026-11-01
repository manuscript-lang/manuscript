import share, Shared from "@std/concurrency/shared.ms"

fn f() Int:
    let items = share([1, 2])
    var inner = items.get()  # error: read-only result
    return inner.length()
