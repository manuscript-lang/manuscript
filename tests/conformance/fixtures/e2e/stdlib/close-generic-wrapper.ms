// conform: tags=scope-cleanup,generics,records,tier-io
// conform: phase=run
// conform: origin=value-semantics-audit
import Closeable from "@std/core.ms"

// A generic wrapper closes the resource its instance holds; a plain instance closes nothing.
type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        print("closed {self.name}")

type Wrap[T]:
    value: T

fn keep[T](v: T) Int:
    _w := Wrap(v)
    return 0

fn keep_optional[T](v: T) Int:
    _o: T? = v
    return 1

fn main() Unit:
    a := keep(Door("wrapped"))
    b := keep_optional(Door("optional"))
    c := keep(5)
    print("end {a + b + c}")
