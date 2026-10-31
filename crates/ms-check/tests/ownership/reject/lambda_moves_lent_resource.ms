import Closeable from "@std/core.ms"

type Door:
    n: Int

impl Closeable for Door:
    var fn close() Unit!:
        return ok(unit)

fn f() Int:
    let wrap = fn(d: Door) Door?: d  # error: cannot move `d` out: a function value only borrows
    let kept = wrap(Door(1))
    return kept.get().n
