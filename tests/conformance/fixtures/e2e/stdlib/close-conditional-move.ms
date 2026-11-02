# conform: tags=scope-cleanup,control-flow,records,tier-io
# conform: phase=run
# conform: origin=close-gap-probes
import stdout from "@std/io/io.ms"
import Closeable from "@std/core.ms"

type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        stdout().write("closed {self.name}\n").get()
        return ok(unit)

impl Door:
    fn id() Int:
        return 1

type Pair:
    left: Door
    n: Int

fn open_handle(name: String) Door:
    return Door(name)

fn consume(d: Door) Int:
    let owned = d
    return owned.id()

fn ret_or_fall(c: Bool) Int:
    let h = open_handle("ret-or-fall")
    if c:
        return consume(h)

    return 0

fn arg_in_branch(c: Bool) Int:
    let h = open_handle("arg-branch")
    if c:
        consume(h)
    return 0

fn into_record(c: Bool) Int:
    let h = open_handle("into-record")

    if c:
        let p = Pair(h, 1)
        return p.n

    return 0

fn in_loop(n: Int) Int:
    var total = 0

    for i in 0..n:
        let h = open_handle("loop-{i}")
        if i % 2 == 0:
            total += consume(h)

    return total

fn moved_always() Int:
    let h = open_handle("always")
    return consume(h)

fn returned(c: Bool) Door:
    let h = open_handle("returned")
    if c:
        return h

    return open_handle("other")

fn else_branch(c: Bool) Int:
    let h = open_handle("else")

    if c:
        return 0
    else:
        return consume(h)

export fn main() Int:
    ret_or_fall(true)
    stdout().write("--ret_or_fall false\n").get()
    ret_or_fall(false)
    stdout().write("--arg_in_branch true\n").get()
    arg_in_branch(true)
    stdout().write("--arg_in_branch false\n").get()
    arg_in_branch(false)
    stdout().write("--into_record true\n").get()
    into_record(true)
    stdout().write("--into_record false\n").get()
    into_record(false)
    stdout().write("--in_loop\n").get()
    in_loop(4)
    stdout().write("--moved_always\n").get()
    moved_always()
    stdout().write("--returned true\n").get()

    let _r = returned(true)
    stdout().write("--returned false\n").get()

    let _r2 = returned(false)
    stdout().write("--else true\n").get()
    else_branch(true)
    stdout().write("--else false\n").get()
    else_branch(false)
    stdout().write("--end\n").get()
    return 0
