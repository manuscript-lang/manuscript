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

fn twice(r: Room) Int:
    xs := keep(r.door)  // error: is moved here but used again
    return xs.length() + keep(r.door).length()
