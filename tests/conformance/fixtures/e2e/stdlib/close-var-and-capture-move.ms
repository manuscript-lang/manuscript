// conform: tags=scope-cleanup,control-flow,closures,records,tier-io
// conform: phase=run
// conform: origin=close-gap-probes
import Closeable from "@std/core.ms"

type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        print("closed {self.name}")
        return ok(unit)

impl Door:
    fn id() Int:
        return 1

fn open_handle(name: String) Door:
    return Door(name)

fn consume(d: Door) Int:
    let owned = d
    return owned.id()

fn var_unmoved() Int:
    var h = open_handle("var-unmoved")
    return h.id()

fn var_moved(c: Bool) Int:
    var h = open_handle("var-moved")
    if c:
        return consume(h)

    return 0

fn var_reassign() Int:
    var h = open_handle("var-old")
    h = open_handle("var-new")
    return h.id()

fn var_move_reassign(c: Bool) Int:
    var h = open_handle("var-first")

    if c:
        consume(h)
        h = open_handle("var-second")

    return h.id()

fn captured(c: Bool) fn() Int:
    let h = open_handle("captured")
    if c:
        return fn: h.id()

    return fn: 0

fn main() Unit:
    var_unmoved()
    print("--var_moved true")
    var_moved(true)
    print("--var_moved false")
    var_moved(false)
    print("--var_reassign")
    var_reassign()
    print("--var_move_reassign true")
    var_move_reassign(true)
    print("--var_move_reassign false")
    var_move_reassign(false)
    print("--captured true")

    let _f = captured(true)
    print("--captured false")

    let _g = captured(false)
    print("--end")
