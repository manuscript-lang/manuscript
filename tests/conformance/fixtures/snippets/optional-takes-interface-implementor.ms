# conform: tags=optional,interfaces,tier-io
# conform: phase=run
# conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"

interface Shape:
    fn area() Int

type Sq:
    n: Int

impl Shape for Sq:
    fn area() Int: self.n * self.n

type Holder:
    s: Shape?

fn pick(b: Bool) Shape?:
    if b: return Sq(3)

    return none

fn take(x: Shape?) Int:
    if let s = x: return s.area()

    return -1

export fn main() Int:
    let h = Holder(Sq(4))
    let t: Shape? = Sq(5)
    var v: Shape? = none
    v = Sq(6)
    (
        stdout()
        .write(
            "{take(pick(true))} {take(pick(false))} {take(Sq(2))} {take(h.s)} {take(t)} {take(v)}\n"
        )
        .get()
    )
    return 0
