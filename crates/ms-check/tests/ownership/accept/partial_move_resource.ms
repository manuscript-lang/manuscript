import Closeable from "@std/core.ms"

type Door:
    id: Int

impl Closeable for Door:
    var fn close() Unit:
        return

type Room:
    door: Door
    spare: Door
    tag: String

type Wrap:
    room: Room
    extra: Door

fn keep(d: Door) List[Door]:
    var xs: List[Door] = []
    xs.append(d)
    return xs

fn take(r: Room) List[Door]:
    return keep(r.door)

fn sibling(r: Room) Int:
    let xs = keep(r.door)
    return xs.length() + r.tag.length()

fn branch(r: Room, flag: Bool) List[Door]:
    var xs: List[Door] = []
    if flag:
        xs.append(r.door)
    return xs

fn nested(w: Wrap) List[Door]:
    return keep(w.room.spare)

fn local() List[Door]:
    let r = Room(Door(1), Door(2), "t")
    return keep(r.spare)
