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

fn captured(r: Room) Int:
    f := fn() List[Door]:
        return keep(r.door)  // error: cannot move the resource
    return f().length()
