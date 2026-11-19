import Closeable from "@std/core.ms"

type Door:
    id: Int

fn move Door.close() Void!:
    return ok()

type Room:
    door: Door
    tag: String

type Guard:
    door: Door

fn move Guard.close() Void!:
    return ok()

fn keep(d: Door) List[Door]:
    var xs: List[Door] = []
    xs.append(d)
    return xs

fn closing(g: Guard) List[Door]:
    return keep(g.door)  // error: cannot move the resource
