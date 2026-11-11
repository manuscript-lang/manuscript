import Closeable from "@std/core.ms"

type Door:
    id: Int

fn var Door.close() Unit!:
    return ok(unit)

type Room:
    door: Door
    tag: String

type Guard:
    door: Door

fn var Guard.close() Unit!:
    return ok(unit)

fn keep(d: Door) List[Door]:
    var xs: List[Door] = []
    xs.append(d)
    return xs

fn closing(g: Guard) List[Door]:
    return keep(g.door)  // error: cannot move the resource
