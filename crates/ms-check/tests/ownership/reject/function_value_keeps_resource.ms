import Closeable from "@std/core.ms"

type Door:
    n: Int

impl Closeable for Door:
    var fn close() Unit:
        return

fn wrap(d: Door) Door?:
    return d

fn apply(f: fn(Door) Door?) Int:
    return f(Door(1)).get().n

fn g() Int:
    return apply(wrap)  # error: `wrap` keeps its parameter `d`
