import Closeable from "@std/core.ms"

type Door:
    n: Int

impl Closeable for Door:
    var fn close() Unit!:
        return ok(unit)

type Room:
    door: Door
    n: Int

fn keep(var d: Door) Door:
    return d  # error: a resource cannot be cloned, so change it in place

fn field(rooms: List[Room]) List[Door]:
    var ys: List[Door] = []
    for r in rooms:
        ys.append(r.door)  # error: a resource cannot be cloned, and it leaves `r` only when `r` is a `let` or a parameter
    return ys

fn looped() Int:
    let xs = [Door(1)]
    var ys: List[Door] = []
    for d in xs:
        ys.append(d)  # error: a resource cannot be cloned, so use `d` in place
    return xs.length() + ys.length()

fn run(f: fn() Door) Int:
    return f().n

fn captured() Int:
    let d = Door(1)
    return run(fn() Door: d)  # error: a resource cannot be cloned; use `d` in place inside the closure
