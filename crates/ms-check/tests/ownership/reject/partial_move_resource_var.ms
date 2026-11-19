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

fn changing() List[Door]:
    var r = Room(Door(1), "t")
    return keep(r.door)  // error: cannot move the resource
