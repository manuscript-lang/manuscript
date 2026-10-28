# conform: tags=scope-cleanup,control-flow,records,tier-io
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

type Pair:
    left: Door
    n: Int

def open_handle(name: String) -> Door:
    return Door(name)

def consume(d: Door) -> Int:
    let owned = d
    return owned.id()

def ret_or_fall(c: Bool) -> Int:
    let h = open_handle("ret-or-fall")
    if c:
        return consume(h)
    return 0

def arg_in_branch(c: Bool) -> Int:
    let h = open_handle("arg-branch")
    if c:
        consume(h)
    return 0

def into_record(c: Bool) -> Int:
    let h = open_handle("into-record")
    if c:
        let p = Pair(h, 1)
        return p.n
    return 0

def in_loop(n: Int) -> Int:
    var total = 0
    for i in 0..n:
        let h = open_handle(f"loop-{i}")
        if i % 2 == 0:
            total += consume(h)
    return total

def moved_always() -> Int:
    let h = open_handle("always")
    return consume(h)

def returned(c: Bool) -> Door:
    let h = open_handle("returned")
    if c:
        return h
    return open_handle("other")

def else_branch(c: Bool) -> Int:
    let h = open_handle("else")
    if c:
        return 0
    else:
        return consume(h)

export def main() -> Int:
    ret_or_fall(True)
    stdout().write("--ret_or_fall false\n").get()
    ret_or_fall(False)
    stdout().write("--arg_in_branch true\n").get()
    arg_in_branch(True)
    stdout().write("--arg_in_branch false\n").get()
    arg_in_branch(False)
    stdout().write("--into_record true\n").get()
    into_record(True)
    stdout().write("--into_record false\n").get()
    into_record(False)
    stdout().write("--in_loop\n").get()
    in_loop(4)
    stdout().write("--moved_always\n").get()
    moved_always()
    stdout().write("--returned true\n").get()
    let _r = returned(True)
    stdout().write("--returned false\n").get()
    let _r2 = returned(False)
    stdout().write("--else true\n").get()
    else_branch(True)
    stdout().write("--else false\n").get()
    else_branch(False)
    stdout().write("--end\n").get()
    return 0
