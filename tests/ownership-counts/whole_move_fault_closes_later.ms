// expect-stdout: close b
// expect-stdout: close a
// expect-stdout: waited: true
// A guarded task faults after moving one resource: the cleanup stack still closes the binding registered after it.
import (
    stdout from "@std/io/io.ms",
    Closeable from "@std/core.ms",
    panic from "@std/core.ms",
    promise from "@std/concurrency/promise.ms",
)

type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        stdout().write("close {self.name}\n").get()
        return ok(unit)

fn faulting() Unit:
    var xs: List[Door] = []
    let a = Door("a")
    let b = Door("b")
    xs.append(a)

    let _n = b.name.length()
    panic("fault after the move")

fn main() Unit:
    let work = promise(fn: ok(faulting()))
    let waited = work.wait()
    stdout().write("waited: {waited.is_error()}\n").get()
