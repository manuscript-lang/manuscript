import Closeable from "@std/core.ms"

type Door:
    n: Int

fn var Door.close() Unit!:
    return ok(unit)

type Bin:
    count: Int

fn Bin.keep(d: Door) Door?:
    return d

fn apply(f: fn(Door) Door?) Int:
    return f(Door(1)).get().n

fn g() Int:
    b := Bin(0)
    return apply(b.keep)  // error: `b.keep` keeps its parameter `d`
