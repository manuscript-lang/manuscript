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

fn twice(r: Room) Int:
    let xs = keep(r.door)  # error: is moved here but used again
    return xs.length() + keep(r.door).length()
