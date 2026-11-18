// conform: tags=scope-cleanup,tier-io
// conform: phase=run
// conform: origin=bug-bash

// A parameter declared `move` is the callee's: when the body only reads it or ignores it, the
// callee closes it at the end, since the caller no longer owns it.
type Door:
    name: String

fn Door.close() Void!:
    print(f"closed {self.name}")

fn ignore(move d: Door) Int:
    return 1

fn read(move d: Door) Int:
    return d.name.length()

fn move Door.consume() Int:
    return 2

fn main() Void:
    print(ignore(Door("a")))
    print(read(Door("bb")))
    c := Door("c")
    print(ignore(c))
    e := Door("e")
    print(e.consume())
    print("end")
