// Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
// expect-mir: "iface.new"
// expect-mir: "call.method"

import stdout from "@std/io/io.ms"

interface Shape:
    fn area() Int

type Sq:
    s: Int

fn Sq.area() Int:
    return self.s * self.s

fn total(x: Shape) Int:
    return x.area()

fn pick(n: Int) Result[Int, Error]:
    if n < 0:
        return error(Error(message: "neg"))

    return ok(n)

fn twice(n: Int) Result[Int, Error]:
    v := pick(n)?
    return ok(v * 2)

fn show(n: Int) Result[Unit, Error]:
    stdout().write("{n}\n")?
    stdout().flush()?

fn main() Unit:
    show(total(Sq(s: 4))).get()
    show(twice(3).get()).get()

    r := twice(0 - 1)

    if v := r:
        show(v).get()
    else:
        show(99).get()
