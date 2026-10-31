import Closeable from "@std/core.ms"

type Door:
    id: Int

impl Closeable for Door:
    var fn close() Unit!:
        return ok(unit)

type Room:
    door: Door
    tag: String

type Wrap:
    room: Room

fn keep(d: Door) List[Door]:
    var xs: List[Door] = []
    xs.append(d)
    return xs

fn rooms(r: Room) List[Room]:
    var xs: List[Room] = []
    xs.append(r)
    return xs

fn both(w: Wrap, flag: Bool) Int:
    if flag:
        return rooms(w.room).length()

    return keep(w.room.door).length()  # error: are both moved out
