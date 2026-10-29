# conform: tags=scope-cleanup,control-flow,closures,records,tier-io
# conform: phase=run
# conform: origin=close-gap-probes
import stdout from "@std/io.ms"
import Closeable from "@std/core.ms"

type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit:
        stdout().write("closed {self.name}\n").get()

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

export fn main() Int:
    var_unmoved()
    stdout().write("--var_moved true\n").get()
    var_moved(true)
    stdout().write("--var_moved false\n").get()
    var_moved(false)
    stdout().write("--var_reassign\n").get()
    var_reassign()
    stdout().write("--var_move_reassign true\n").get()
    var_move_reassign(true)
    stdout().write("--var_move_reassign false\n").get()
    var_move_reassign(false)
    stdout().write("--captured true\n").get()

    let _f = captured(true)
    stdout().write("--captured false\n").get()

    let _g = captured(false)
    stdout().write("--end\n").get()
    return 0
