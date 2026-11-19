import Closeable from "@std/core.ms"

type Door:
    id: Int

fn move Door.close() Void!:
    return ok()

type Room:
    door: Door
    tag: String

fn keep(move d: Door) List[Door]:
    var xs: List[Door] = []
    xs.append(d)
    return xs

fn each(rooms: List[Room]) Int:
    var n = 0
    for r in rooms:
        n += keep(r.door).length()  // error: cannot move the resource
    return n
