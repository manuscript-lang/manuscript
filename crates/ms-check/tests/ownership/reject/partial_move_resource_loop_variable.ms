import Closeable from "@std/core.ms"

type Door:
    id: Int

impl Closeable for Door:
    var fn close() Unit!:
        return ok(unit)

type Room:
    door: Door
    tag: String

fn keep(d: Door) List[Door]:
    var xs: List[Door] = []
    xs.append(d)
    return xs

fn each(rooms: List[Room]) Int:
    var n = 0
    for r in rooms:
        n += keep(r.door).length()  # error: cannot move the resource
    return n
