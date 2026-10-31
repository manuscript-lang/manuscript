import Closeable from "@std/core.ms"

type Door:
    id: Int

impl Closeable for Door:
    var fn close() Unit:
        return

type Room:
    door: Door
    tag: String

type Guard:
    door: Door

impl Closeable for Guard:
    var fn close() Unit:
        return

fn keep(d: Door) List[Door]:
    var xs: List[Door] = []
    xs.append(d)
    return xs

fn closing(g: Guard) List[Door]:
    return keep(g.door)  # error: cannot move the resource
