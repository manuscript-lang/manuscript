// conform: tags=scope-cleanup,generics,interfaces,tier-io
// conform: phase=run
// conform: origin=bug-bash

// A parameter declared `move` is the callee's: when the body only reads it or ignores it, the
// callee closes it at the end, since the caller no longer owns it. The same holds for interface and
// generic parameters, and a generic function can return a moved parameter.
import Closeable from "@std/core.ms"

type Door:
    name String

fn move Door.close() Void!:
    print(f"closed {self.name}")

fn ignore(move d Door) Int:
    return 1

fn read(move d Door) Int:
    return d.name.length()

fn move Door.consume() Int:
    return 2

fn ignore_view(move c Closeable) Int:
    return 3

fn ignore_generic[T](move x T) Int:
    return 4

fn identity[T](move x T) T:
    return x

fn second[T](move x T, move y T) T:
    return y

fn main() Void:
    print(ignore(Door("a")))
    print(read(Door("bb")))
    c := Door("c")
    print(ignore(c))
    e := Door("e")
    print(e.consume())
    f := Door("f")
    print(ignore_view(f))
    print(ignore_generic(Door("g")))
    print(identity(Door("h")).name)
    print(identity("text"))
    s := second(Door("p"), Door("q"))
    print(s.name)
    print("end")
