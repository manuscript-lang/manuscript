import Promise, promise from "@std/concurrency/promise.ms"
import Closeable from "@std/core.ms"

type Door:
    count: Int

impl Closeable for Door:
    var fn close() Unit!:
        return ok(unit)

fn size(door: Door) Int!:
    return ok(door.count)

fn f() Int!:
    door := Door(count: 1)
    p := promise(fn: size(door))
    return p.wait()

type Holder:
    p: Promise[Int]

fn work_n(n: Int) Int!:
    return ok(n + 1)

fn start_copy(k: Int) Holder:
    n := k * 2
    p := promise(fn: work_n(n))
    return Holder(p: p)
