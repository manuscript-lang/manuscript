import Closeable from "@std/core.ms"

type Door:
    n: Int

impl Closeable for Door:
    var fn close() Unit!:
        return ok(unit)

type Bin:
    count: Int

impl Bin:
    fn keep(d: Door) Door?:
        return d

fn apply(f: fn(Door) Door?) Int:
    return f(Door(1)).get().n

fn g() Int:
    let b = Bin(0)
    return apply(b.keep)  # error: `b.keep` keeps its parameter `d`
