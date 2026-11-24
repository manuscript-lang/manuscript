// conform: tags=scope-cleanup,generics,records,tier-io
// conform: phase=run
// conform: origin=value-semantics-audit
import Closeable from "@std/core.ms"

// A generic wrapper closes the resource its instance holds; a plain instance closes nothing.
type Door:
    name String

fn move Door.close() Void!:
    print(f"closed {self.name}")

type Wrap[T]:
    value T

fn keep[T](move v T) Int:
    _w := Wrap(v)
    return 0

fn keep_optional[T](move v T) Int:
    _o T? := v
    return 1

fn main() Void:
    a := keep(Door("wrapped"))
    b := keep_optional(Door("optional"))
    c := keep(5)
    print(f"end {a + b + c}")
