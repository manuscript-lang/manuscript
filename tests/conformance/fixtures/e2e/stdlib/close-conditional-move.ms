// conform: tags=scope-cleanup,control-flow,records,tier-io
// conform: phase=run
// conform: origin=close-gap-probes
import Closeable from "@std/core.ms"

type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        print("closed {self.name}")

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

fn main() Unit:
    ret_or_fall(true)
    print("--ret_or_fall false")
    ret_or_fall(false)
    print("--arg_in_branch true")
    arg_in_branch(true)
    print("--arg_in_branch false")
    arg_in_branch(false)
    print("--into_record true")
    into_record(true)
    print("--into_record false")
    into_record(false)
    print("--in_loop")
    in_loop(4)
    print("--moved_always")
    moved_always()
    print("--returned true")

    let _r = returned(true)
    print("--returned false")

    let _r2 = returned(false)
    print("--else true")
    else_branch(true)
    print("--else false")
    else_branch(false)
    print("--end")
