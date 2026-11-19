import Closeable from "@std/core.ms"

type Handle:
    items: List[Int]

fn move Handle.close() Void!:
    return ok()

fn keep(xs: List[Int]) List[Int]:
    return xs

fn closing(h: Handle) List[Int]:
    return keep(h.items)
