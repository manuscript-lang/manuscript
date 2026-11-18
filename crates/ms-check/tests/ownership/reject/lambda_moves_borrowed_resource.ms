import Closeable from "@std/core.ms"

type Door:
    n: Int

fn var Door.close() Void!:
    return ok()

fn f() Int:
    wrap := fn(d: Door) Door?: d  // error: cannot move `d` out: this function type borrows its argument
    kept := wrap(Door(1))
    return kept.get().n
