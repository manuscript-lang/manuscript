import Closeable from "@std/core.ms"

type Door:
    id: Int

impl Closeable for Door:
    var fn close() Unit:
        return

type Room:
    door: Door
    tag: String

fn keep(d: Door) List[Door]:
    var xs: List[Door] = []
    xs.append(d)
    return xs

fn changing() List[Door]:
    var r = Room(Door(1), "t")
    return keep(r.door)  # error: cannot move the resource
