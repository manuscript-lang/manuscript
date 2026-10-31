import Closeable from "@std/core.ms"

type Handle:
    items: List[Int]

impl Closeable for Handle:
    var fn close() Unit!:
        return ok(unit)

fn keep(xs: List[Int]) List[Int]:
    return xs

fn closing(h: Handle) List[Int]:
    return keep(h.items)  # error: only a whole variable can move
