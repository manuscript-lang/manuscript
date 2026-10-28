# conform: tags=scope-cleanup,control-flow,closures,records,tier-io
# conform: phase=run
# conform: origin=close-gap-probes
from "@std/io.ms" import stdout
from "@std/core.ms" import Closeable

type Door:
    name: String

impl Closeable for Door:
    var def close() -> Unit:
        stdout().write(f"closed {self.name}\n").get()

impl Door:
    def id() -> Int:
        return 1

def open_handle(name: String) -> Door:
    return Door(name)

def consume(d: Door) -> Int:
    let owned = d
    return owned.id()

def var_unmoved() -> Int:
    var h = open_handle("var-unmoved")
    return h.id()

def var_moved(c: Bool) -> Int:
    var h = open_handle("var-moved")
    if c:
        return consume(h)
    return 0

def var_reassign() -> Int:
    var h = open_handle("var-old")
    h = open_handle("var-new")
    return h.id()

def var_move_reassign(c: Bool) -> Int:
    var h = open_handle("var-first")
    if c:
        consume(h)
        h = open_handle("var-second")
    return h.id()

def captured(c: Bool) -> Callable[[], Int]:
    let h = open_handle("captured")
    if c:
        return lambda: h.id()
    return lambda: 0

export def main() -> Int:
    var_unmoved()
    stdout().write("--var_moved true\n").get()
    var_moved(True)
    stdout().write("--var_moved false\n").get()
    var_moved(False)
    stdout().write("--var_reassign\n").get()
    var_reassign()
    stdout().write("--var_move_reassign true\n").get()
    var_move_reassign(True)
    stdout().write("--var_move_reassign false\n").get()
    var_move_reassign(False)
    stdout().write("--captured true\n").get()
    let _f = captured(True)
    stdout().write("--captured false\n").get()
    let _g = captured(False)
    stdout().write("--end\n").get()
    return 0
