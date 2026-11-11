import Closeable from "@std/core.ms"

type Handle:
    items: List[Int]

fn var Handle.close() Unit!:
    return ok(unit)

fn keep(xs: List[Int]) List[Int]:
    return xs

fn closing(h: Handle) List[Int]:
    return keep(h.items)
