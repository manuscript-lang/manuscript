from "@std/shared.ms" import share, Shared

def f() -> Int:
    let items = share([1, 2])
    var inner = items.get()  # error: read-only result
    return inner.length()
